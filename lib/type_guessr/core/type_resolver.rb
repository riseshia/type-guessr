# frozen_string_literal: true

require_relative "variable_index"
require_relative "scope_resolver"
require_relative "rbs_provider"
require_relative "types"

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
        return [] if !type_matcher

        type_matcher.find_matching_types(method_calls)
      end

      private

      # Find the best definition before the hover line
      # Returns the definition with the highest line number that is <= hover_line
      # @param definitions [Array<Hash>] array of definition hashes with :def_line key
      # @param hover_line [Integer] the hover line number
      # @return [Hash, nil] the best matching definition or nil
      def find_best_definition_before(definitions, hover_line)
        definitions
          .select { |def_info| def_info[:def_line] <= hover_line }
          .max_by { |def_info| def_info[:def_line] }
      end

      # Get the direct type for a variable (from literal assignment or .new call)
      # @param variable_name [String] the variable name
      # @param hover_line [Integer] the hover line number
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param file_path [String, nil] optional file path (reserved for future use)
      # @return [TypeGuessr::Core::Types::Type, nil] the guessed type object or nil
      def get_direct_type(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        # First, check if there's a type defined exactly at the hover line
        # This handles reassignment cases where we hover on a write node
        direct_at_line = find_direct_type_from_index(
          variable_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id,
          hover_line: hover_line
        )

        # If we found a type at the exact hover line, return it immediately
        # This ensures reassignments show the new type, not the old one
        if direct_at_line && direct_at_line != Types::Unknown.instance
          # Verify this type is actually at the hover line, not just before it
          definitions_at_line = @index.find_definitions(
            var_name: variable_name,
            file_path: file_path,
            scope_type: scope_type,
            scope_id: scope_id
          ).select { |d| d[:def_line] == hover_line }

          # If no definition at this exact line in method call index,
          # it means this is a write node with a literal/new assignment
          # Return the type we found
          return direct_at_line if definitions_at_line.empty?
        end

        # Find definitions matching the exact scope (from method call index)
        definitions = @index.find_definitions(
          var_name: variable_name,
          file_path: file_path,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # Find the closest definition before the hover line
        best_match = find_best_definition_before(definitions, hover_line)

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

        # Return the direct type we found earlier
        return direct_at_line if direct_at_line && direct_at_line != Types::Unknown.instance

        inferred_from_call = infer_type_from_call_assignment(
          variable_name: variable_name,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path
        )

        return inferred_from_call if inferred_from_call && inferred_from_call != Types::Unknown.instance

        direct_at_line
      end

      def rbs_provider
        RBSProvider.instance
      end

      def infer_type_from_call_assignment(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        call_info = @index.find_call_assignment_at_location(
          var_name: variable_name,
          scope_type: scope_type,
          max_line: hover_line,
          scope_id: scope_id
        )

        return Types::Unknown.instance if !call_info

        receiver_var = call_info[:receiver_var]
        methods = call_info[:methods]
        return Types::Unknown.instance if !receiver_var || !methods || methods.empty?

        receiver_type = resolve_receiver_type_for_call(
          receiver_var: receiver_var,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path,
          visited: {}
        )

        apply_method_chain(receiver_type, methods)
      end

      def resolve_receiver_type_for_call(receiver_var:, hover_line:, scope_type:, scope_id:, file_path:, visited:)
        return Types::Unknown.instance if visited[receiver_var]

        visited[receiver_var] = true

        type = get_direct_type(
          variable_name: receiver_var,
          hover_line: hover_line,
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path
        )

        type || Types::Unknown.instance
      ensure
        visited.delete(receiver_var)
      end

      def apply_method_chain(receiver_type, methods)
        current = receiver_type || Types::Unknown.instance

        methods.each do |method_name|
          return Types::Unknown.instance if !current.is_a?(Types::ClassInstance)

          current = rbs_provider.get_method_return_type(current.name, method_name)
          return Types::Unknown.instance if current == Types::Unknown.instance
        end

        current
      end

      # Search type index directly for variables that have types but no method calls
      # @param variable_name [String] the variable name
      # @param scope_type [Symbol] the scope type
      # @param scope_id [String] the scope identifier
      # @param hover_line [Integer] the hover line number
      # @return [TypeGuessr::Core::Types::Type, nil] the guessed type object or nil
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
      def collect_method_calls(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
        # Find definitions matching the exact scope
        definitions = @index.find_definitions(
          var_name: variable_name,
          file_path: file_path,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # Find the closest definition that appears before the hover line
        best_match = find_best_definition_before(definitions, hover_line)

        return [] if !best_match

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
      end
    end
  end
end
