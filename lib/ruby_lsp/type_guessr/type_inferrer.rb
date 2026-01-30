# frozen_string_literal: true

require "ruby_lsp/type_inferrer"

module RubyLsp
  module TypeGuessr
    # Custom TypeInferrer that enhances ruby-lsp's type inference with TypeGuessr's
    # IR-based heuristic inference. Used by Go to Definition and other features.
    class TypeInferrer < ::RubyLsp::TypeInferrer
      # Core layer shortcuts
      Types = ::TypeGuessr::Core::Types
      IR = ::TypeGuessr::Core::IR
      NodeContextHelper = ::TypeGuessr::Core::NodeContextHelper
      private_constant :Types, :IR, :NodeContextHelper

      def initialize(index, runtime_adapter)
        super(index)
        @runtime_adapter = runtime_adapter
      end

      # Override to add TypeGuessr's heuristic type inference
      # Returns nil when type cannot be determined (no fallback to ruby-lsp's default)
      #
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [GuessedType, nil] The inferred type or nil if unknown
      def infer_receiver_type(node_context)
        guess_type_from_ir(node_context)
      end

      private

      # Attempt to guess type using IR-based inference
      # Returns GuessedType only when type can be resolved
      #
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [GuessedType, nil] The guessed type or nil if unknown
      def guess_type_from_ir(node_context)
        node = node_context.node

        # For CallNode, we need to infer the receiver's type
        target_node = if node.is_a?(Prism::CallNode)
                        extract_receiver_variable(node)
                      else
                        node
                      end

        return nil unless target_node && variable_node?(target_node)

        # Find the IR node
        ir_node = find_ir_node(target_node, node_context)
        return nil unless ir_node

        # Infer type from IR node
        result = @runtime_adapter.infer_type(ir_node)
        return nil if result.type.is_a?(Types::Unknown)

        # Convert to ruby-lsp's Type format
        type_string = result.type.to_s
        return nil if type_string == "untyped" || type_string.empty?

        GuessedType.new(type_string)
      end

      # Find the IR node corresponding to a Prism node
      # @param node [Prism::Node] The Prism node
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [TypeGuessr::Core::IR::Node, nil] The IR node or nil
      def find_ir_node(node, node_context)
        scope_id = NodeContextHelper.generate_scope_id(node_context)
        node_hash = NodeContextHelper.generate_node_hash(node, node_context)
        return nil unless node_hash

        node_key = "#{scope_id}:#{node_hash}"
        @runtime_adapter.find_node_by_key(node_key)
      end

      # Extract the variable node from a CallNode's receiver
      # @param call_node [Prism::CallNode] The call node
      # @return [Prism::Node, nil] The receiver variable node or nil
      def extract_receiver_variable(call_node)
        receiver = call_node.receiver
        return nil unless receiver

        # Unwrap parentheses if present
        if receiver.is_a?(Prism::ParenthesesNode)
          statements = receiver.body
          receiver = statements.body.first if statements.is_a?(Prism::StatementsNode) && statements.body.length == 1
        end

        receiver
      end

      # Check if the node is a variable node that we can analyze
      # @param node [Prism::Node] The node to check
      # @return [Boolean] true if the node is a variable node
      def variable_node?(node)
        case node
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode,
             Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode,
             Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
             Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
             Prism::KeywordRestParameterNode, Prism::BlockParameterNode
          true
        else
          false
        end
      end
    end
  end
end
