# frozen_string_literal: true

require "prism"
require_relative "type_matcher"

# Explicitly require core dependencies to ensure they're loaded
# even when this file is loaded independently (e.g., by Ruby LSP)
# Load version first to ensure TypeGuessr module exists
require_relative "../../type_guessr/version" if !defined?(TypeGuessr::VERSION)
require_relative "../../type_guessr/core/type_resolver"
require_relative "../../type_guessr/core/variable_index"
require_relative "../../type_guessr/core/scope_resolver"

module RubyLsp
  module TypeGuessr
    # Resolves variable types by analyzing definitions and method calls
    # LSP adapter that extracts data from Prism nodes and delegates to core TypeResolver
    class VariableTypeResolver
      def initialize(node_context, global_state = nil)
        @node_context = node_context
        @global_state = global_state
        @core_resolver = ::TypeGuessr::Core::TypeResolver.new
      end

      # Resolve type information for a variable node
      # @param node [Prism::Node] the variable node
      # @return [Hash] hash with :direct_type and :method_calls keys
      def resolve_type(node)
        variable_name = extract_variable_name(node)
        return nil if !variable_name

        location = node.location
        hover_line = location.start_line

        scope_type = determine_scope_type(variable_name)
        scope_id = generate_scope_id(scope_type)

        # Delegate to core resolver
        @core_resolver.resolve_type(
          variable_name: variable_name,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id
        )
      end

      # Infer type from method calls using TypeMatcher
      # @param method_calls [Array<String>] array of method names
      # @return [Array<String>] array of matching type names
      def infer_type_from_methods(method_calls)
        return [] if !@global_state
        return [] if method_calls.empty?

        index = @global_state.index
        matcher = TypeMatcher.new(index)
        @core_resolver.infer_type_from_methods(method_calls, matcher)
      end

      private

      # Extract variable name from a node
      # @param node [Prism::Node] the node to extract from
      # @return [String, nil] the variable name or nil
      def extract_variable_name(node)
        case node
        when ::Prism::LocalVariableReadNode, ::Prism::LocalVariableWriteNode
          node.name.to_s
        when ::Prism::LocalVariableTargetNode
          node.name.to_s
        when ::Prism::RequiredParameterNode, ::Prism::OptionalParameterNode
          node.name.to_s
        when ::Prism::RestParameterNode
          node.name&.to_s
        when ::Prism::RequiredKeywordParameterNode, ::Prism::OptionalKeywordParameterNode
          node.name.to_s
        when ::Prism::KeywordRestParameterNode
          node.name&.to_s
        when ::Prism::BlockParameterNode
          node.name&.to_s
        when ::Prism::InstanceVariableReadNode, ::Prism::InstanceVariableWriteNode,
             ::Prism::InstanceVariableTargetNode
          node.name.to_s
        when ::Prism::ClassVariableReadNode, ::Prism::ClassVariableWriteNode,
             ::Prism::ClassVariableTargetNode
          node.name.to_s
        when ::Prism::GlobalVariableReadNode, ::Prism::GlobalVariableWriteNode,
             ::Prism::GlobalVariableTargetNode
          node.name.to_s
        when ::Prism::SelfNode
          "self"
        when ::Prism::ForwardingParameterNode
          "..."
        end
      end

      # Determine the scope type based on variable name
      # @param var_name [String] the variable name
      # @return [Symbol] the scope type
      def determine_scope_type(var_name)
        ::TypeGuessr::Core::ScopeResolver.determine_scope_type(var_name)
      end

      # Generate scope ID from node context
      # - For instance/class variables: "ClassName"
      # - For local variables: "ClassName#method_name"
      # @param scope_type [Symbol] the scope type
      # @return [String] the scope identifier
      def generate_scope_id(scope_type)
        nesting = @node_context.nesting
        # nesting may contain strings or objects with name method
        class_path = nesting.map { |n| n.is_a?(String) ? n : n.name }.join("::")

        # Use surrounding_method to find enclosing method name for local variables
        method_name = scope_type == :local_variables ? @node_context.surrounding_method : nil

        ::TypeGuessr::Core::ScopeResolver.generate_scope_id(
          scope_type,
          class_path: class_path,
          method_name: method_name
        )
      end
    end
  end
end
