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
      # Initialize with node context and either global_state or index
      # @param node_context [RubyLsp::NodeContext] the node context
      # @param global_state_or_index [Object, nil] either GlobalState (has .index) or RubyIndexer::Index directly
      def initialize(node_context, global_state_or_index = nil)
        @node_context = node_context
        @index = extract_index(global_state_or_index)
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
        return [] if !@index
        return [] if method_calls.empty?

        matcher = TypeMatcher.new(@index)
        @core_resolver.infer_type_from_methods(method_calls, matcher)
      end

      # Get entries for type names to enable linking to definitions
      # @param type_names [Array<String>] array of type names
      # @return [Hash<String, Entry>] map of type name to entry
      def get_type_entries(type_names)
        return {} if !@index

        matcher = TypeMatcher.new(@index)
        entries = {}
        type_names.each do |type_name|
          next if type_name == TypeMatcher::TRUNCATED_MARKER

          entry = matcher.get_entry(type_name)
          entries[type_name] = entry if entry
        end
        entries
      end

      private

      # Extract index from global_state or use directly if it's already an index
      # @param global_state_or_index [Object, nil] either GlobalState or Index
      # @return [RubyIndexer::Index, nil] the index or nil
      def extract_index(global_state_or_index)
        return nil if global_state_or_index.nil?

        # If it responds to .index, it's a GlobalState
        if global_state_or_index.respond_to?(:index)
          global_state_or_index.index
        else
          # Otherwise assume it's already an index
          global_state_or_index
        end
      end

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
