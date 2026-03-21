# frozen_string_literal: true

require "prism"
require_relative "context"
require_relative "literal_converter"
require_relative "variable_converter"
require_relative "container_mutation_converter"
require_relative "call_converter"
require_relative "control_flow_converter"
require_relative "definition_converter"
require_relative "registration"
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
