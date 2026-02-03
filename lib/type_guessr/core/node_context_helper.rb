# frozen_string_literal: true

require_relative "node_key_generator"

module TypeGuessr
  module Core
    # Helper module for generating scope IDs and node hashes from Prism nodes and NodeContext.
    # Extracted from Hover and TypeInferrer to eliminate code duplication.
    #
    # This module provides framework-agnostic utilities that bridge between ruby-lsp's
    # NodeContext and TypeGuessr's IR node key format.
    module NodeContextHelper
      module_function def generate_scope_id(node_context, exclude_method: false)
        class_path = node_context.nesting.map do |n|
          n.is_a?(String) ? n : n.name.to_s
        end.join("::")

        method_name = exclude_method ? nil : node_context.surrounding_method

        if method_name
          "#{class_path}##{method_name}"
        else
          class_path
        end
      end

      # Generate node_hash from Prism node to match IR node_hash format
      # @param node [Prism::Node] The Prism node
      # @param node_context [RubyLsp::NodeContext] The context (for block param detection and nesting)
      # @return [String, nil] The node hash or nil for unsupported node types
      module_function def generate_node_hash(node, node_context)
        offset = node.location.start_offset
        case node
        when Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode
          NodeKeyGenerator.local_write(node.name, offset)
        when Prism::LocalVariableReadNode
          NodeKeyGenerator.local_read(node.name, offset)
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode
          NodeKeyGenerator.ivar_write(node.name, offset)
        when Prism::InstanceVariableReadNode
          NodeKeyGenerator.ivar_read(node.name, offset)
        when Prism::ClassVariableWriteNode, Prism::ClassVariableTargetNode
          NodeKeyGenerator.cvar_write(node.name, offset)
        when Prism::ClassVariableReadNode
          NodeKeyGenerator.cvar_read(node.name, offset)
        when Prism::GlobalVariableWriteNode, Prism::GlobalVariableTargetNode
          NodeKeyGenerator.global_write(node.name, offset)
        when Prism::GlobalVariableReadNode
          NodeKeyGenerator.global_read(node.name, offset)
        when Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
             Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
             Prism::KeywordRestParameterNode, Prism::BlockParameterNode
          # Check if this is a block parameter (parent is BlockParametersNode)
          if block_parameter?(node, node_context)
            index = block_parameter_index(node, node_context)
            NodeKeyGenerator.bparam(index, offset)
          else
            NodeKeyGenerator.param(node.name, offset)
          end
        when Prism::ForwardingParameterNode
          NodeKeyGenerator.param(:"...", offset)
        when Prism::CallNode
          # Use message_loc for accurate offset
          call_offset = node.message_loc&.start_offset || offset
          NodeKeyGenerator.call(node.name, call_offset)
        when Prism::DefNode
          # Use name_loc for accurate offset
          def_offset = node.name_loc&.start_offset || offset
          NodeKeyGenerator.def_node(node.name, def_offset)
        when Prism::SelfNode
          class_path = node_context.nesting.map do |n|
            n.is_a?(String) ? n : n.name.to_s
          end.join("::")
          NodeKeyGenerator.self_node(class_path, offset)
        end
      end

      # Check if a parameter node is inside a block (not a method definition)
      # @param node [Prism::Node] The parameter node
      # @param node_context [RubyLsp::NodeContext] The context
      # @return [Boolean] true if inside a block
      module_function def block_parameter?(node, node_context)
        call_node = node_context.call_node
        return false unless call_node&.block

        # Check if this parameter is in the block's parameters
        block_params = call_node.block.parameters&.parameters
        return false unless block_params

        all_params = collect_block_params(block_params)
        all_params.include?(node)
      end

      # Get the index of a block parameter
      # @param node [Prism::Node] The parameter node
      # @param node_context [RubyLsp::NodeContext] The context
      # @return [Integer] The parameter index
      module_function def block_parameter_index(node, node_context)
        call_node = node_context.call_node
        return 0 unless call_node&.block

        block_params = call_node.block.parameters&.parameters
        return 0 unless block_params

        all_params = collect_block_params(block_params)
        all_params.index(node) || 0
      end

      # Collect all parameters from block parameters node
      # Uses respond_to? guards for safety across different Prism versions
      # @param block_params [Prism::ParametersNode] The block parameters
      # @return [Array<Prism::Node>] All parameter nodes
      module_function def collect_block_params(block_params)
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
