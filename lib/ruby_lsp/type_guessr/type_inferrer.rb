# frozen_string_literal: true

require "ruby_lsp/type_inferrer"
require_relative "variable_type_resolver"
require_relative "variable_node_types"
require_relative "../../type_guessr/core/type_formatter"

module RubyLsp
  module TypeGuessr
    # Custom TypeInferrer that inherits from ruby-lsp's TypeInferrer.
    # This allows TypeGuessr to hook into ruby-lsp's type inference system
    # for enhanced heuristic type guessing while reusing Type and GuessedType classes.
    class TypeInferrer < ::RubyLsp::TypeInferrer
      # Core layer shortcut
      TypeFormatter = ::TypeGuessr::Core::TypeFormatter
      private_constant :TypeFormatter
      # Infers the type of a node based on its context.
      # Override this method to add heuristic type inference.
      # Falls back to super when type cannot be uniquely determined.
      #
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [Type, GuessedType, nil] The guessed type or nil if unknown
      def infer_receiver_type(node_context)
        guessed_type = guess_type_from_variable(node_context)
        return guessed_type if guessed_type

        super
      end

      private

      # Attempt to guess type using VariableTypeResolver
      # Returns GuessedType only when exactly one type matches
      #
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [GuessedType, nil] The guessed type or nil if ambiguous/unknown
      def guess_type_from_variable(node_context)
        node = node_context.node

        # For CallNode, try to infer the receiver's type
        target_node = if node.is_a?(::Prism::CallNode)
                        extract_receiver_variable(node)
                      else
                        node
                      end

        return nil if !target_node || !variable_node?(target_node)

        resolver = VariableTypeResolver.new(node_context, @index)
        type_info = resolver.resolve_type(target_node)
        return nil if !type_info

        # Check for direct type first
        direct_type = type_info[:direct_type]
        if direct_type
          # Convert Types object to string format for ruby-lsp's Type.new
          type_string = TypeFormatter.format(direct_type)
          return Type.new(type_string)
        end

        # Try to infer from method calls
        method_calls = type_info[:method_calls]
        return nil if method_calls.empty?

        matching_types = resolver.infer_type_from_methods(method_calls)

        # Only return when exactly one type matches (unambiguous)
        return nil if matching_types.size != 1

        Type.new(TypeFormatter.format(matching_types.first))
      end

      # Extract the variable node from a CallNode's receiver
      # Handles parenthesized expressions like (foo).bar
      #
      # @param call_node [Prism::CallNode] The call node
      # @return [Prism::Node, nil] The receiver variable node or nil
      def extract_receiver_variable(call_node)
        receiver = call_node.receiver
        return nil if !receiver

        # Unwrap parentheses if present
        if receiver.is_a?(::Prism::ParenthesesNode)
          statements = receiver.body
          receiver = statements.body.first if statements.is_a?(::Prism::StatementsNode) && statements.body.length == 1
        end

        receiver
      end

      # Check if the node is a variable node that we can analyze
      #
      # @param node [Prism::Node] The node to check
      # @return [Boolean] true if the node is a variable node
      def variable_node?(node)
        VariableNodeTypes.variable_node?(node)
      end
    end
  end
end
