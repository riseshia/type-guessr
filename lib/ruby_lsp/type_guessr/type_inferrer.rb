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
      private_constant :Types, :IR

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
        scope_id = generate_scope_id(node_context)
        node_hash = generate_node_hash(node, node_context)
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

      # Generate scope_id from node_context
      # Format: "ClassName#method_name" or "ClassName" or "#method_name" or ""
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [String] The scope identifier
      def generate_scope_id(node_context)
        class_path = node_context.nesting.map do |n|
          n.is_a?(String) ? n : n.name.to_s
        end.join("::")

        method_name = node_context.surrounding_method

        if method_name
          "#{class_path}##{method_name}"
        else
          class_path
        end
      end

      # Generate node_hash from Prism node to match IR node_hash format
      # @param node [Prism::Node] The Prism node
      # @param node_context [RubyLsp::NodeContext] The context (for block param detection)
      # @return [String, nil] The node hash or nil
      def generate_node_hash(node, node_context)
        line = node.location.start_line
        case node
        when Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode
          "local_write:#{node.name}:#{line}"
        when Prism::LocalVariableReadNode
          "local_read:#{node.name}:#{line}"
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode
          "ivar_write:#{node.name}:#{line}"
        when Prism::InstanceVariableReadNode
          "ivar_read:#{node.name}:#{line}"
        when Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
             Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
             Prism::KeywordRestParameterNode, Prism::BlockParameterNode
          # Check if this is a block parameter
          if block_parameter?(node, node_context)
            index = block_parameter_index(node, node_context)
            "bparam:#{index}:#{line}"
          else
            "param:#{node.name}:#{line}"
          end
        end
      end

      # Check if a parameter node is inside a block (not a method definition)
      # @param node [Prism::Node] The parameter node
      # @param node_context [RubyLsp::NodeContext] The context
      # @return [Boolean] true if inside a block
      def block_parameter?(node, node_context)
        call_node = node_context.call_node
        return false unless call_node&.block

        block_params = call_node.block.parameters&.parameters
        return false unless block_params

        all_params = collect_block_params(block_params)
        all_params.include?(node)
      end

      # Get the index of a block parameter
      # @param node [Prism::Node] The parameter node
      # @param node_context [RubyLsp::NodeContext] The context
      # @return [Integer] The parameter index
      def block_parameter_index(node, node_context)
        call_node = node_context.call_node
        return 0 unless call_node&.block

        block_params = call_node.block.parameters&.parameters
        return 0 unless block_params

        all_params = collect_block_params(block_params)
        all_params.index(node) || 0
      end

      # Collect all parameters from block parameters node
      # @param block_params [Prism::ParametersNode] The block parameters
      # @return [Array<Prism::Node>] All parameter nodes
      def collect_block_params(block_params)
        params = []
        params.concat(block_params.requireds) if block_params.respond_to?(:requireds)
        params.concat(block_params.optionals) if block_params.respond_to?(:optionals)
        params << block_params.rest if block_params.respond_to?(:rest) && block_params.rest
        params.concat(block_params.posts) if block_params.respond_to?(:posts)
        params.concat(block_params.keywords) if block_params.respond_to?(:keywords)
        params << block_params.keyword_rest if block_params.respond_to?(:keyword_rest) && block_params.keyword_rest
        params << block_params.block if block_params.respond_to?(:block) && block_params.block
        params.compact
      end
    end
  end
end
