# frozen_string_literal: true

require "prism"
require_relative "variable_index"
require_relative "type_matcher"

module RubyLsp
  module Guesser
    # Resolves variable types by analyzing definitions and method calls
    # Handles variable name extraction, scope resolution, and type inference
    class VariableTypeResolver
      def initialize(node_context, global_state = nil)
        @node_context = node_context
        @global_state = global_state
        @index = VariableIndex.instance
      end

      # Resolve type information for a variable node
      # @param node [Prism::Node] the variable node
      # @return [Hash] hash with :direct_type and :method_calls keys
      def resolve_type(node)
        variable_name = extract_variable_name(node)
        return nil unless variable_name

        direct_type = get_direct_type(variable_name, node)
        method_calls = collect_method_calls(variable_name, node)

        {
          variable_name: variable_name,
          direct_type: direct_type,
          method_calls: method_calls
        }
      end

      # Infer type from method calls using TypeMatcher
      # @param method_calls [Array<String>] array of method names
      # @return [Array<String>] array of matching type names
      def infer_type_from_methods(method_calls)
        return [] unless @global_state
        return [] if method_calls.empty?

        index = @global_state.index
        matcher = TypeMatcher.new(index)
        matcher.find_matching_types(method_calls)
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
        when ::Prism::InstanceVariableReadNode
          node.name.to_s
        when ::Prism::ClassVariableReadNode
          node.name.to_s
        when ::Prism::GlobalVariableReadNode
          node.name.to_s
        when ::Prism::SelfNode
          "self"
        when ::Prism::ForwardingParameterNode
          "..."
        end
      end

      # Get the direct type for a variable (from literal assignment or .new call)
      # @param variable_name [String] the variable name
      # @param node [Prism::Node] the node
      # @return [String, nil] the inferred type or nil
      def get_direct_type(variable_name, node)
        location = node.location
        hover_line = location.start_line

        scope_type = determine_scope_type(variable_name)
        scope_id = generate_scope_id(scope_type)

        # First, try to find definitions from method call index
        definitions = @index.find_definitions(
          var_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # If no exact match, try broader search
        if definitions.empty?
          definitions = @index.find_definitions(
            var_name: variable_name,
            scope_type: scope_type
          )
        end

        # Find the closest definition before the hover line
        best_match = definitions
                     .select { |def_info| def_info[:def_line] <= hover_line }
                     .max_by { |def_info| def_info[:def_line] }

        if best_match
          # Get the type for this definition
          type = @index.get_variable_type(
            file_path: best_match[:file_path],
            scope_type: best_match[:scope_type],
            scope_id: best_match[:scope_id],
            var_name: variable_name,
            def_line: best_match[:def_line],
            def_column: best_match[:def_column]
          )
          return type if type
        end

        # Fallback: search type index directly (for variables with type but no method calls)
        find_direct_type_from_index(variable_name, scope_type, scope_id, hover_line)
      end

      # Search type index directly for variables that have types but no method calls
      # @param variable_name [String] the variable name
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param hover_line [Integer] the hover line number
      # @return [String, nil] the inferred type or nil
      def find_direct_type_from_index(variable_name, scope_type, scope_id, hover_line)
        # Use the public API to find variable type at location
        @index.find_variable_type_at_location(
          var_name: variable_name,
          scope_type: scope_type,
          max_line: hover_line,
          scope_id: scope_id
        )
      end

      # Collect method calls for a variable
      # @param variable_name [String] the variable name
      # @param node [Prism::Node] the node
      # @return [Array<String>] array of method names
      def collect_method_calls(variable_name, node)
        location = node.location
        hover_line = location.start_line

        scope_type = determine_scope_type(variable_name)
        scope_id = generate_scope_id(scope_type)

        # Try to find definitions matching the exact scope
        definitions = @index.find_definitions(
          var_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # If no exact match, try without scope_id (broader search)
        if definitions.empty?
          definitions = @index.find_definitions(
            var_name: variable_name,
            scope_type: scope_type
          )
        end

        # Find the closest definition that appears before the hover line
        best_match = definitions
                     .select { |def_info| def_info[:def_line] <= hover_line }
                     .max_by { |def_info| def_info[:def_line] }

        if best_match
          # Use the exact variable definition location for precise results
          calls = @index.get_method_calls(
            file_path: best_match[:file_path],
            scope_type: best_match[:scope_type],
            scope_id: best_match[:scope_id],
            var_name: variable_name,
            def_line: best_match[:def_line],
            def_column: best_match[:def_column]
          )
          calls.map { |call| call[:method] }.uniq
        else
          # Fallback: collect method calls from all matching definitions
          method_names = []
          definitions.each do |def_info|
            calls = @index.get_method_calls(
              file_path: def_info[:file_path],
              scope_type: def_info[:scope_type],
              scope_id: def_info[:scope_id],
              var_name: variable_name,
              def_line: def_info[:def_line],
              def_column: def_info[:def_column]
            )
            method_names.concat(calls.map { |call| call[:method] })
          end
          method_names.uniq.take(20)
        end
      end

      # Determine the scope type based on variable name
      # @param var_name [String] the variable name
      # @return [Symbol] the scope type
      def determine_scope_type(var_name)
        ScopeResolver.determine_scope_type(var_name)
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

        # Try to find enclosing method name for local variables
        method_name = scope_type == :local_variables ? @node_context.call_node&.name&.to_s : nil

        ScopeResolver.generate_scope_id(
          scope_type,
          class_path: class_path,
          method_name: method_name
        )
      end
    end
  end
end
