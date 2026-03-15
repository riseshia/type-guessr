# frozen_string_literal: true

# This file is loaded in the Rails runner process (not the LSP server)
# via RunnerClient.register_server_addon.
# RubyLsp::Rails::ServerAddon is already defined when this file is required.

module RubyLsp
  module TypeGuessr
    # ServerAddon that runs inside the Rails runner process.
    # Queries ActiveRecord runtime for model metadata (columns, enums, associations, scopes).
    class RailsServerAddon < ::RubyLsp::Rails::ServerAddon
      def name
        "TypeGuessr"
      end

      def execute(request, params)
        case request
        when "model_metadata"
          handle_model_metadata(params)
        end
      end

      private def handle_model_metadata(params)
        class_name = params[:name]
        klass = class_name.constantize

        return send_error_response("#{class_name} is not an ActiveRecord model") unless active_record_model?(klass)

        send_result({
                      columns: extract_columns(klass),
                      enums: extract_enums(klass),
                      associations: extract_associations(klass),
                      scopes: extract_scopes(klass)
                    })
      rescue NameError
        send_error_response("#{class_name} is not a valid class")
      rescue StandardError => e
        send_error_response("#{e.class}: #{e.message}")
      end

      private def active_record_model?(klass)
        klass < ::ActiveRecord::Base
      rescue StandardError
        false
      end

      private def extract_columns(klass)
        klass.columns.map do |col|
          [col.name, col.type.to_s, col.null]
        end
      end

      private def extract_enums(klass)
        return {} unless klass.respond_to?(:defined_enums)

        klass.defined_enums
      end

      private def extract_associations(klass)
        klass.reflect_on_all_associations.map do |assoc|
          {
            name: assoc.name.to_s,
            macro: assoc.macro.to_s,
            class_name: assoc.class_name
          }
        end
      rescue StandardError
        []
      end

      private def extract_scopes(klass)
        enum_values = klass.respond_to?(:defined_enums) ? klass.defined_enums.values.flat_map(&:keys) : []
        exclude = Set.new(enum_values + enum_values.map { |v| "not_#{v}" })

        klass.singleton_methods(false)
             .map(&:to_s)
             .reject { |m| exclude.include?(m) || m.start_with?("find_by_", "create_", "build_") }
      rescue StandardError
        []
      end
    end
  end
end
