# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Shared constants for TypeGuessr addon
    module Constants
      # Mapping from node type symbols to Prism node classes
      # - keys: Used for dispatcher event handler registration (hover.rb)
      # - values: Used for extending Ruby LSP's ALLOWED_TARGETS (addon.rb)
      HOVER_NODE_MAPPING = {
        local_variable_read: Prism::LocalVariableReadNode,
        local_variable_write: Prism::LocalVariableWriteNode,
        local_variable_target: Prism::LocalVariableTargetNode,
        instance_variable_read: Prism::InstanceVariableReadNode,
        instance_variable_write: Prism::InstanceVariableWriteNode,
        instance_variable_target: Prism::InstanceVariableTargetNode,
        class_variable_read: Prism::ClassVariableReadNode,
        class_variable_write: Prism::ClassVariableWriteNode,
        class_variable_target: Prism::ClassVariableTargetNode,
        global_variable_read: Prism::GlobalVariableReadNode,
        global_variable_write: Prism::GlobalVariableWriteNode,
        global_variable_target: Prism::GlobalVariableTargetNode,
        required_parameter: Prism::RequiredParameterNode,
        optional_parameter: Prism::OptionalParameterNode,
        rest_parameter: Prism::RestParameterNode,
        required_keyword_parameter: Prism::RequiredKeywordParameterNode,
        optional_keyword_parameter: Prism::OptionalKeywordParameterNode,
        keyword_rest_parameter: Prism::KeywordRestParameterNode,
        block_parameter: Prism::BlockParameterNode,
        forwarding_parameter: Prism::ForwardingParameterNode,
        call: Prism::CallNode,
        def: Prism::DefNode,
        self: Prism::SelfNode
      }.freeze
    end
  end
end
