# frozen_string_literal: true

require "prism"

module RubyLsp
  module TypeGuessr
    # Shared definition of variable node types supported by TypeGuessr
    # This module provides a centralized list of Prism node types that represent variables
    module VariableNodeTypes
      # All Prism node types that represent variables
      CLASSES = [
        ::Prism::LocalVariableReadNode,
        ::Prism::LocalVariableWriteNode,
        ::Prism::LocalVariableTargetNode,
        ::Prism::InstanceVariableReadNode,
        ::Prism::InstanceVariableWriteNode,
        ::Prism::InstanceVariableTargetNode,
        ::Prism::ClassVariableReadNode,
        ::Prism::ClassVariableWriteNode,
        ::Prism::ClassVariableTargetNode,
        ::Prism::GlobalVariableReadNode,
        ::Prism::GlobalVariableWriteNode,
        ::Prism::GlobalVariableTargetNode,
        ::Prism::RequiredParameterNode,
        ::Prism::OptionalParameterNode,
        ::Prism::RestParameterNode,
        ::Prism::RequiredKeywordParameterNode,
        ::Prism::OptionalKeywordParameterNode,
        ::Prism::KeywordRestParameterNode,
        ::Prism::BlockParameterNode,
        ::Prism::SelfNode,
        ::Prism::ForwardingParameterNode,
      ].freeze

      # Check if the given node is a variable node
      # @param node [Prism::Node] the node to check
      # @return [Boolean] true if the node is a variable node
      def self.variable_node?(node)
        CLASSES.any? { |klass| node.is_a?(klass) }
      end
    end
  end
end
