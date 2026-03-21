# frozen_string_literal: true

require "prism"
require_relative "context"
require_relative "literal_converter"
require_relative "variable_converter"
require_relative "container_mutation_converter"
require_relative "call_converter"
require_relative "control_flow_converter"
require_relative "definition_converter"
require_relative "../ir"
require_relative "../types"

module TypeGuessr
  module Core
    module Converter
      # Converts Prism AST to IR graph (reverse dependency graph)
      # Each IR node points to nodes it depends on
      class PrismConverter
        def initialize
          @literal_type_cache = {}
        end

        # Convert Prism AST to IR graph
        # @param prism_node [Prism::Node] Prism AST node
        # @param context [Context] Conversion context
        # @return [IR::Node, nil] IR node
        def convert(prism_node, context = Context.new)
          node = case prism_node
                 when Prism::IntegerNode, Prism::FloatNode, Prism::StringNode,
                      Prism::SymbolNode, Prism::TrueNode, Prism::FalseNode,
                      Prism::NilNode, Prism::InterpolatedStringNode, Prism::RangeNode,
                      Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode,
                      Prism::ImaginaryNode, Prism::RationalNode,
                      Prism::XStringNode, Prism::InterpolatedXStringNode
                   convert_literal(prism_node)

                 when Prism::ArrayNode
                   convert_array_literal(prism_node, context)

                 when Prism::HashNode
                   convert_hash_literal(prism_node, context)

                 when Prism::KeywordHashNode
                   convert_keyword_hash(prism_node, context)

                 when Prism::LocalVariableWriteNode
                   convert_local_variable_write(prism_node, context)

                 when Prism::LocalVariableReadNode
                   convert_local_variable_read(prism_node, context)

                 when Prism::InstanceVariableWriteNode
                   convert_instance_variable_write(prism_node, context)

                 when Prism::InstanceVariableReadNode
                   convert_instance_variable_read(prism_node, context)

                 when Prism::ClassVariableWriteNode
                   convert_class_variable_write(prism_node, context)

                 when Prism::ClassVariableReadNode
                   convert_class_variable_read(prism_node, context)

                 # Compound assignments (||=, &&=, +=, etc.)
                 when Prism::LocalVariableOrWriteNode
                   convert_local_variable_or_write(prism_node, context)

                 when Prism::LocalVariableAndWriteNode
                   convert_local_variable_and_write(prism_node, context)

                 when Prism::LocalVariableOperatorWriteNode
                   convert_local_variable_operator_write(prism_node, context)

                 when Prism::InstanceVariableOrWriteNode
                   convert_instance_variable_or_write(prism_node, context)

                 when Prism::InstanceVariableAndWriteNode
                   convert_instance_variable_and_write(prism_node, context)

                 when Prism::InstanceVariableOperatorWriteNode
                   convert_instance_variable_operator_write(prism_node, context)

                 when Prism::CallNode
                   # Unwrap visibility modifier: `private def foo` → treat as `def foo`
                   if visibility_modifier_with_def?(prism_node)
                     convert_def(prism_node.arguments.arguments.first, context,
                                 module_function: prism_node.name == :module_function)
                   else
                     convert_call(prism_node, context)
                   end

                 when Prism::IfNode
                   convert_if(prism_node, context)

                 when Prism::UnlessNode
                   convert_unless(prism_node, context)

                 when Prism::CaseNode
                   convert_case(prism_node, context)

                 when Prism::CaseMatchNode
                   convert_case_match(prism_node, context)

                 when Prism::StatementsNode
                   convert_statements(prism_node, context)

                 when Prism::DefNode
                   convert_def(prism_node, context)

                 when Prism::ConstantReadNode, Prism::ConstantPathNode
                   convert_constant_read(prism_node, context)

                 when Prism::ConstantWriteNode
                   convert_constant_write(prism_node, context)

                 when Prism::ClassNode, Prism::ModuleNode
                   convert_class_or_module(prism_node, context)

                 when Prism::SingletonClassNode
                   convert_singleton_class(prism_node, context)

                 when Prism::ReturnNode
                   # Return statement - wrap in ReturnNode to track explicit returns
                   value_node = if prism_node.arguments&.arguments&.first
                                  convert(prism_node.arguments.arguments.first, context)
                                else
                                  # return with no value returns nil
                                  IR::LiteralNode.new(
                                    Types::ClassInstance.for("NilClass"),
                                    nil,
                                    nil,
                                    [],
                                    convert_loc(prism_node.location)
                                  )
                                end
                   IR::ReturnNode.new(
                     value_node,
                     [],
                     convert_loc(prism_node.location)
                   )

                 when Prism::SelfNode
                   # self keyword - returns the current class instance or singleton
                   IR::SelfNode.new(
                     context.current_class_name || "Object",
                     context.in_singleton_method,
                     [],
                     convert_loc(prism_node.location)
                   )

                 when Prism::BeginNode
                   convert_begin(prism_node, context)

                 when Prism::RescueNode
                   # Rescue clause - convert body statements
                   convert_statements_body(prism_node.statements&.body, context)

                 when Prism::OrNode
                   convert_or_node(prism_node, context)

                 when Prism::AndNode
                   convert_and_node(prism_node, context)

                 when Prism::IndexOrWriteNode
                   convert_index_or_write(prism_node, context)

                 when Prism::ParenthesesNode
                   convert(prism_node.body, context) if prism_node.body

                 when Prism::MultiWriteNode
                   convert_multi_write(prism_node, context)
                 end

          register_node(node, context) if node
          node
        end

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

        # Check if a CallNode is a visibility modifier wrapping a def (e.g., `private def foo`)
        private def visibility_modifier_with_def?(prism_node)
          %i[private protected public module_function].include?(prism_node.name) &&
            prism_node.receiver.nil? &&
            prism_node.arguments&.arguments&.size == 1 &&
            prism_node.arguments.arguments.first.is_a?(Prism::DefNode)
        end
      end
    end
  end
end
