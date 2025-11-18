# frozen_string_literal: true

require_relative "variable_index"
require_relative "scope_resolver"

module TypeGuessr
  module Core
    # Resolves variable types by analyzing definitions and method calls
    # Pure functional interface with no LSP dependencies
    class TypeResolver
      def initialize(variable_index = VariableIndex.instance)
        @index = variable_index
      end

      # Resolve type information for a variable
      # @param variable_name [String] the variable name
      # @param hover_line [Integer] the line number where hover occurs
      # @param scope_type [Symbol] the scope type (:local_variables, :instance_variables, :class_variables)
      # @param scope_id [String] the scope identifier
      # @param file_path [String, nil] optional file path for more precise lookup
      # @return [Hash] hash with :direct_type and :method_calls keys
      def resolve_type(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        direct_type = get_direct_type(
          variable_name: variable_name,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path
        )

        method_calls = collect_method_calls(
          variable_name: variable_name,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path
        )

        {
          variable_name: variable_name,
          direct_type: direct_type,
          method_calls: method_calls
        }
      end

      # Infer type from method calls using a type matcher
      # @param method_calls [Array<String>] array of method names
      # @param type_matcher [Object] type matcher that responds to find_matching_types
      # @return [Array<String>] array of matching type names
      def infer_type_from_methods(method_calls, type_matcher)
        return [] if method_calls.empty?
        return [] unless type_matcher

        type_matcher.find_matching_types(method_calls)
      end

      private

      # Get the direct type for a variable (from literal assignment or .new call)
      # @param variable_name [String] the variable name
      # @param hover_line [Integer] the hover line number
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param file_path [String, nil] optional file path (reserved for future use)
      # @return [String, nil] the inferred type or nil
      # rubocop:disable Lint/UnusedMethodArgument
      def get_direct_type(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        # rubocop:enable Lint/UnusedMethodArgument
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
        find_direct_type_from_index(
          variable_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id,
          hover_line: hover_line
        )
      end

      # Search type index directly for variables that have types but no method calls
      # @param variable_name [String] the variable name
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param hover_line [Integer] the hover line number
      # @return [String, nil] the inferred type or nil
      def find_direct_type_from_index(variable_name:, scope_type:, scope_id:, hover_line:)
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
      # @param hover_line [Integer] the hover line number
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param file_path [String, nil] optional file path (reserved for future use)
      # @return [Array<String>] array of method names
      # rubocop:disable Lint/UnusedMethodArgument
      def collect_method_calls(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        # rubocop:enable Lint/UnusedMethodArgument
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
    end
  end
end
