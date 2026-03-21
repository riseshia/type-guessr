# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Node registration and location conversion methods for PrismConverter
      class PrismConverter
        private def convert_loc(prism_location)
          prism_location.start_offset
        end

        # Register node in location_index and registries during conversion
        # This eliminates the need for a separate tree traversal after conversion
        private def register_node(node, context)
          return unless context.location_index

          case node
          when IR::DefNode
            # DefNode uses singleton-adjusted method_scope for registration
            method_scope = singleton_scope_for(context.current_class_name || "", singleton: node.singleton)
            context.location_index.add(context.file_path, node, method_scope)
            register_method(node, context)

            # Register params (created directly, not via convert)
            # Use method scope with method name for params
            param_scope = method_scope.empty? ? "##{node.name}" : "#{method_scope}##{node.name}"
            node.params&.each do |param|
              context.location_index.add(context.file_path, param, param_scope)
            end
          when IR::ClassModuleNode
            # ClassModuleNode uses parent scope for registration
            context.location_index.add(context.file_path, node, context.scope_id)
            register_class_module(node, context)
          when IR::CallNode
            context.location_index.add(context.file_path, node, context.scope_id)
            # Register block params (created directly, not via convert)
            node.block_params&.each do |param|
              context.location_index.add(context.file_path, param, context.scope_id)
            end
          when IR::InstanceVariableWriteNode
            context.location_index.add(context.file_path, node, context.scope_id)
            context.ivar_registry&.register(node.class_name, node.name, node, file_path: context.file_path)
          when IR::ClassVariableWriteNode
            context.location_index.add(context.file_path, node, context.scope_id)
            context.cvar_registry&.register(node.class_name, node.name, node, file_path: context.file_path)
          else
            # All other nodes (MergeNode, LiteralNode, etc.)
            context.location_index.add(context.file_path, node, context.scope_id)
          end
        end

        # Register method in method_registry
        # Only registers top-level methods; class methods are handled by register_class_module
        private def register_method(node, context)
          return unless context.method_registry

          # Only register top-level methods (no class context)
          return unless (context.current_class_name || "").empty?

          context.method_registry.register("", node.name.to_s, node, file_path: context.file_path)
        end

        # Register methods from a class/module in method_registry
        private def register_class_module(node, context)
          return unless context.method_registry

          # Build the full class path from parent context + node name
          parent_path = context.current_class_name || ""
          class_path = parent_path.empty? ? node.name : "#{parent_path}::#{node.name}"

          # Register each method in the class (nested classes are handled recursively via convert)
          node.methods&.each do |method|
            next if method.is_a?(IR::ClassModuleNode)

            method_scope = singleton_scope_for(class_path, singleton: method.singleton)
            context.method_registry.register(method_scope, method.name.to_s, method, file_path: context.file_path)

            # module_function: also register as singleton method
            if method.module_function
              singleton_scope = singleton_scope_for(class_path, singleton: true)
              context.method_registry.register(singleton_scope, method.name.to_s, method, file_path: context.file_path)
            end
          end
        end

        # Build singleton class scope for method registration/lookup
        # Singleton methods use "<Class:ClassName>" suffix to match RubyIndexer convention
        # @param scope [String] Base scope (e.g., "RBS::Environment")
        # @param singleton [Boolean] Whether the method is a singleton method
        # @return [String] Scope with singleton class suffix if applicable
        private def singleton_scope_for(scope, singleton:)
          return scope unless singleton

          parent_name = IR.extract_last_name(scope) || "Object"
          scope.empty? ? "<Class:Object>" : "#{scope}::<Class:#{parent_name}>"
        end
      end
    end
  end
end
