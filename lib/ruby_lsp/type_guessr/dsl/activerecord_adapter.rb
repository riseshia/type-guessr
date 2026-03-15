# frozen_string_literal: true

require_relative "ar_type_mapper"
require_relative "ar_schema_watcher"

module RubyLsp
  module TypeGuessr
    module Dsl
      # ActiveRecord DSL adapter.
      # Discovers AR models, fetches metadata via ServerAddon,
      # and registers column/enum/association/scope types.
      class ActiveRecordAdapter
        BOOL_TYPE = ::TypeGuessr::Core::Types::Union.new([
                                                           ::TypeGuessr::Core::Types::ClassInstance.for("TrueClass"),
                                                           ::TypeGuessr::Core::Types::ClassInstance.for("FalseClass"),
                                                         ]).freeze

        SERVER_ADDON_NAME = "TypeGuessr"

        def initialize(project_root:, cache_dir: nil)
          @project_root = project_root
          @schema_watcher = ArSchemaWatcher.new(project_root, cache_dir: cache_dir)
          @registered_classes = []
          @log_callback = nil
        end

        def on_log(&block)
          @log_callback = block
        end

        def applicable?
          File.directory?(File.join(@project_root, "app", "models"))
        end

        # Register AR::Base common class methods with SelfType.
        # Called once. User.where → Relation[User] via SelfType substitution.
        def register_base_methods(signature_registry:)
          base = "ActiveRecord::Base"
          self_type = ::TypeGuessr::Core::Types::SelfType.instance
          relation_of_self = ::TypeGuessr::Core::Types::ClassInstance.for(
            "ActiveRecord::Relation", { Elem: self_type }
          )
          nullable_self = ::TypeGuessr::Core::Types::Union.new([
                                                                 self_type,
                                                                 ::TypeGuessr::Core::Types::ClassInstance.for("NilClass"),
                                                               ])
          int_type = ::TypeGuessr::Core::Types::ClassInstance.for("Integer")
          bool_type = BOOL_TYPE
          array_of_self = ::TypeGuessr::Core::Types::ClassInstance.for("Array")

          # --- Class methods ---

          # Returning Relation[self]
          %w[
            where all order limit offset select distinct group having reorder reverse_order
            none unscoped reselect extending joins left_joins left_outer_joins
            includes eager_load preload references readonly lock create_with rewhere
            or and not invert_where merge
          ].each do |m|
            signature_registry.register_gem_class_method(base, m, relation_of_self, force: true)
          end

          # Returning self?
          %w[first last second third forty_two take find_by find_sole_by].each do |m|
            signature_registry.register_gem_class_method(base, m, nullable_self, force: true)
          end

          # Returning self
          %w[
            first! last! take! sole find_by! find
            create create! new
            find_or_create_by find_or_create_by! find_or_initialize_by
            create_or_find_by create_or_find_by!
          ].each do |m|
            signature_registry.register_gem_class_method(base, m, self_type, force: true)
          end

          # Returning Integer
          %w[count update_all delete_all].each do |m|
            signature_registry.register_gem_class_method(base, m, int_type, force: true)
          end

          # Returning Array
          %w[ids pluck destroy_all].each do |m|
            signature_registry.register_gem_class_method(base, m, array_of_self, force: true)
          end

          # Returning bool
          %w[exists? any? many? none? empty?].each do |m|
            signature_registry.register_gem_class_method(base, m, bool_type, force: true)
          end

          # --- Instance methods ---

          # Returning bool
          %w[
            save save! update update! toggle! touch
            new_record? persisted? destroyed? changed? previously_new_record? frozen?
            has_changes_to_save? saved_changes? valid? invalid?
          ].each do |m|
            signature_registry.register_gem_method(base, m, bool_type, force: true)
          end

          # Returning self
          %w[destroy destroy! reload toggle increment decrement increment! decrement!].each do |m|
            signature_registry.register_gem_method(base, m, self_type, force: true)
          end

          log("Registered AR::Base common methods (SelfType)")
        end

        # Cache check → cache hit: restore, cache miss + runner_client: fetch → register → save.
        def register_models(runner_client:, signature_registry:, code_index:)
          cached = @schema_watcher.load_cache
          if cached
            apply_model_data(cached, signature_registry, code_index)
            log("Loaded #{@registered_classes.size} models from DSL cache (fast path)")
            return
          end

          return unless runner_client

          register_server_addon(runner_client)
          models = discover_models
          return if models.empty?

          data = fetch_all_metadata(runner_client, models)
          apply_model_data(data, signature_registry, code_index)
          @schema_watcher.save_cache(data) unless data.empty?
          log("Registered #{@registered_classes.size} models via ServerAddon")
        end

        def changed?
          @schema_watcher.changed?
        end

        # Build-then-swap: fetch new data first, then purge old + apply new.
        def refresh(runner_client:, signature_registry:, code_index:)
          return unless runner_client

          register_server_addon(runner_client)
          models = discover_models
          new_data = fetch_all_metadata(runner_client, models)

          # Swap: purge old, apply new
          @registered_classes.each { |cn| code_index.unregister_method_classes(cn) }
          @registered_classes.clear
          apply_model_data(new_data, signature_registry, code_index)
          @schema_watcher.save_cache(new_data) unless new_data.empty?
          log("Refreshed #{@registered_classes.size} models via ServerAddon")
        end

        private def log(message)
          @log_callback&.call(message)
        end

        private def register_server_addon(runner_client)
          addon_path = File.expand_path("../rails_server_addon", __dir__)
          runner_client.register_server_addon(addon_path)
        rescue StandardError => e
          log("Failed to register ServerAddon: #{e.message}")
        end

        private def discover_models
          models_dir = File.join(@project_root, "app", "models")
          return [] unless File.directory?(models_dir)

          Dir.glob(File.join(models_dir, "**", "*.rb")).filter_map do |path|
            relative = path.delete_prefix("#{models_dir}/").delete_suffix(".rb")
            next if relative.start_with?("concerns/")
            next if relative == "application_record"

            relative.split("/").map { |part| camelize(part) }.join("::")
          end
        end

        private def fetch_all_metadata(runner_client, models)
          data = {}

          models.each do |class_name|
            result = runner_client.delegate_request(
              server_addon_name: SERVER_ADDON_NAME,
              request_name: "model_metadata",
              name: class_name
            )
            next unless result.is_a?(Hash)

            model_data = build_model_data(class_name, result)
            data[class_name] = model_data unless model_data.empty?
          rescue StandardError => e
            log("Failed to fetch metadata for #{class_name}: #{e.message}")
          end

          data
        end

        private def build_model_data(class_name, result)
          methods = {}
          build_column_methods(methods, result[:columns] || result["columns"] || [])
          build_enum_methods(methods, class_name, result[:enums] || result["enums"] || {})
          build_association_methods(methods, result[:associations] || result["associations"] || [])
          build_scope_methods(methods, class_name, result[:scopes] || result["scopes"] || [])
          methods
        end

        private def build_column_methods(methods, columns)
          columns.each do |col|
            col_name, col_type, nullable = col
            col_name = col_name.to_s
            nullable = true if nullable.nil?

            # Reader: user.name → String?
            methods[col_name] = { "kind" => "column", "type" => col_type.to_s, "nullable" => nullable }

            # Predicate: user.name? → bool
            methods["#{col_name}?"] = { "kind" => "column_predicate" }

            # Dirty tracking
            methods["#{col_name}_changed?"] = { "kind" => "column_predicate" }
            methods["#{col_name}_previously_changed?"] = { "kind" => "column_predicate" }
            methods["saved_change_to_#{col_name}?"] = { "kind" => "column_predicate" }
            methods["will_save_change_to_#{col_name}?"] = { "kind" => "column_predicate" }
            methods["#{col_name}_was"] = { "kind" => "column", "type" => col_type.to_s, "nullable" => true }
            methods["#{col_name}_in_database"] = { "kind" => "column", "type" => col_type.to_s, "nullable" => true }
            methods["#{col_name}_before_last_save"] = { "kind" => "column", "type" => col_type.to_s, "nullable" => true }
          end
        end

        private def build_enum_methods(methods, class_name, enums)
          enums.each do |attr_name, values|
            methods[attr_name.to_s] = { "kind" => "enum_reader", "type" => "string", "nullable" => true }

            values.each_key do |value_name|
              methods["#{value_name}?"] = { "kind" => "enum_predicate" }
              methods["#{value_name}!"] = { "kind" => "enum_bang" }
              methods["scope:#{value_name}"] = { "kind" => "enum_scope", "class_name" => class_name }
            end
          end
        end

        private def build_association_methods(methods, associations)
          associations.each do |assoc|
            name = (assoc[:name] || assoc["name"]).to_s
            macro = (assoc[:macro] || assoc["macro"]).to_s
            target = assoc[:class_name] || assoc["class_name"]

            # Reader: user.posts / user.profile
            methods[name] = { "kind" => "association", "macro" => macro, "target" => target }

            # Derived methods for singular associations (has_one, belongs_to)
            next unless %w[has_one belongs_to].include?(macro)

            methods["build_#{name}"] = { "kind" => "association_builder", "target" => target }
            methods["create_#{name}"] = { "kind" => "association_builder", "target" => target }
            methods["create_#{name}!"] = { "kind" => "association_builder", "target" => target }
            methods["reload_#{name}"] = { "kind" => "association", "macro" => macro, "target" => target }
          end
        end

        private def build_scope_methods(methods, class_name, scopes)
          scopes.each do |scope_name|
            methods["scope:#{scope_name}"] = { "kind" => "scope", "class_name" => class_name }
          end
        end

        private def apply_model_data(data, signature_registry, code_index)
          data.each do |class_name, methods|
            methods.each do |method_name, info|
              case info["kind"]
              when "column"
                return_type = ArTypeMapper.map(info["type"], nullable: info.fetch("nullable", true))
                register_instance_method(class_name, method_name, return_type, signature_registry, code_index)
              when "enum_reader"
                return_type = ArTypeMapper.map("string", nullable: true)
                register_instance_method(class_name, method_name, return_type, signature_registry, code_index)
              when "column_predicate"
                register_instance_method(class_name, method_name, BOOL_TYPE, signature_registry, code_index)
              when "enum_predicate"
                register_instance_method(class_name, method_name, BOOL_TYPE, signature_registry, code_index)
              when "enum_bang"
                register_instance_method(
                  class_name, method_name,
                  ::TypeGuessr::Core::Types::Unknown.instance,
                  signature_registry, code_index
                )
              when "enum_scope"
                scope_name = method_name.delete_prefix("scope:")
                register_class_scope(info["class_name"], scope_name, signature_registry)
              when "association"
                register_association(class_name, method_name, info["macro"], info["target"],
                                     signature_registry, code_index)
              when "association_builder"
                target_type = ::TypeGuessr::Core::Types::ClassInstance.for(info["target"])
                register_instance_method(class_name, method_name, target_type, signature_registry, code_index)
              when "scope"
                scope_name = method_name.delete_prefix("scope:")
                register_class_scope(info["class_name"], scope_name, signature_registry)
              end
            end

            @registered_classes << class_name
          end
        end

        private def register_instance_method(class_name, method_name, return_type, signature_registry, code_index)
          signature_registry.register_gem_method(class_name, method_name, return_type, force: true)
          code_index.register_method_class(class_name, method_name)
        end

        private def register_class_scope(class_name, scope_name, signature_registry)
          return_type = ::TypeGuessr::Core::Types::ClassInstance.for(
            "ActiveRecord::Relation",
            { Elem: ::TypeGuessr::Core::Types::ClassInstance.for(class_name) }
          )
          signature_registry.register_gem_class_method(class_name, scope_name, return_type, force: true)
        end

        private def register_association(class_name, assoc_name, macro, target, signature_registry, code_index)
          return_type = case macro
                        when "has_many", "has_and_belongs_to_many"
                          ::TypeGuessr::Core::Types::ClassInstance.for(
                            "ActiveRecord::Associations::CollectionProxy",
                            { Elem: ::TypeGuessr::Core::Types::ClassInstance.for(target) }
                          )
                        when "has_one", "belongs_to"
                          ::TypeGuessr::Core::Types::Union.new([
                                                                 ::TypeGuessr::Core::Types::ClassInstance.for(target),
                                                                 ::TypeGuessr::Core::Types::ClassInstance.for("NilClass"),
                                                               ])
                        else
                          ::TypeGuessr::Core::Types::Unknown.instance
                        end

          register_instance_method(class_name, assoc_name, return_type, signature_registry, code_index)
        end

        private def camelize(str)
          str.split("_").map(&:capitalize).join
        end
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
