# frozen_string_literal: true

require "singleton"

module TypeGuessr
  module Core
    # Thread-safe singleton index to store variable definitions and their method calls
    # Organized by scope type (instance/local/class variables) and scope ID
    # Structure:
    # {
    #   instance_variables: { file_path => { scope_id => { var_name => { "line:col" => [calls] } } } },
    #   local_variables: { file_path => { scope_id => { var_name => { "line:col" => [calls] } } } },
    #   class_variables: { file_path => { scope_id => { var_name => { "line:col" => [calls] } } } }
    # }
    class VariableIndex
      include Singleton

      def initialize
        @index = {
          instance_variables: {},
          local_variables: {},
          class_variables: {}
        }
        @types = {
          instance_variables: {},
          local_variables: {},
          class_variables: {}
        }
        @call_assignments = {
          instance_variables: {},
          local_variables: {},
          class_variables: {}
        }
        @mutex = Mutex.new
      end

      # Add call assignment info for a variable definition.
      # Used for inferring types like: result = name.upcase.length
      #
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variables, :local_variables, or :class_variables
      # @param scope_id [String] the scope identifier
      # @param var_name [String] the assigned variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @param receiver_var [String] the receiver variable name (e.g., "name")
      # @param methods [Array<String>] method chain (e.g., ["upcase", "length"])
      def add_call_assignment(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:, receiver_var:,
                              methods:)
        @mutex.synchronize do
          nested = ensure_nested_hash(@call_assignments[scope_type], file_path, scope_id, var_name)
          def_key = "#{def_line}:#{def_column}"
          nested[def_key] = {
            receiver_var: receiver_var,
            methods: methods
          }
        end
      end

      # Find the call assignment info at a specific location (line number).
      # Searches for the closest assignment before the specified line.
      #
      # @param var_name [String] the variable name
      # @param scope_type [Symbol] :instance_variables, :local_variables, or :class_variables
      # @param max_line [Integer] the maximum line number (finds closest definition before this line)
      # @param scope_id [String] the scope identifier
      # @return [Hash, nil] call assignment info or nil
      def find_call_assignment_at_location(var_name:, scope_type:, max_line:, scope_id:)
        @mutex.synchronize do
          scope_types = @call_assignments[scope_type]
          return nil if !scope_types

          best_info = nil
          best_line = 0

          scope_types.each_value do |scopes|
            next if !scopes.key?(scope_id) || !scopes[scope_id].key?(var_name)

            scopes[scope_id][var_name].each do |def_key, info|
              line, _column = def_key.split(":").map(&:to_i)
              if line <= max_line && line > best_line
                best_info = info
                best_line = line
              end
            end
          end

          best_info
        end
      end

      # Add a method call for a variable
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param scope_id [String] the scope identifier (e.g., "Recipe", "Recipe#initialize")
      # @param var_name [String] the variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @param method_name [String] the method being called
      # @param call_line [Integer] the line where the method is called
      # @param call_column [Integer] the column where the method is called
      def add_method_call(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:, method_name:,
                          call_line:, call_column:)
        @mutex.synchronize do
          nested = ensure_nested_hash(@index[scope_type], file_path, scope_id, var_name)

          def_key = "#{def_line}:#{def_column}"
          nested[def_key] ||= []

          call_info = {
            method: method_name,
            line: call_line,
            column: call_column
          }

          calls = nested[def_key]
          calls << call_info if !calls.include?(call_info)
        end
      end

      # Get method calls for a variable
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param scope_id [String] the scope identifier
      # @param var_name [String] the variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @return [Array<Hash>] array of method call information
      def get_method_calls(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:)
        @mutex.synchronize do
          def_key = "#{def_line}:#{def_column}"
          @index.dig(scope_type, file_path, scope_id, var_name, def_key) || []
        end
      end

      # Find all variable definitions matching the given criteria
      # @param var_name [String] the variable name
      # @param file_path [String, nil] optional file path filter
      # @param scope_type [Symbol, nil] optional scope type filter
      # @param scope_id [String, nil] optional scope identifier filter
      # @return [Array<Hash>] array of definition info
      def find_definitions(var_name:, file_path: nil, scope_type: nil, scope_id: nil)
        @mutex.synchronize do
          definitions = []

          scope_types = scope_type ? [scope_type] : @index.keys

          scope_types.each do |stype|
            scope_index = @index[stype]

            scope_index.each do |fpath, scopes|
              next if file_path && fpath != file_path

              scopes.each do |sid, vars|
                next if scope_id && sid != scope_id
                next if !vars.key?(var_name)

                vars[var_name].each_key do |def_key|
                  line, column = def_key.split(":").map(&:to_i)
                  definitions << {
                    file_path: fpath,
                    scope_type: stype,
                    scope_id: sid,
                    def_line: line,
                    def_column: column
                  }
                end
              end
            end
          end

          definitions
        end
      end

      # Add a variable type for a variable definition
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param scope_id [String] the scope identifier
      # @param var_name [String] the variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @param type [TypeGuessr::Core::Types::Type] the guessed type object
      def add_variable_type(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:, type:)
        @mutex.synchronize do
          nested = ensure_nested_hash(@types[scope_type], file_path, scope_id, var_name)

          def_key = "#{def_line}:#{def_column}"
          nested[def_key] = type
        end
      end

      # Get the type for a variable definition
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param scope_id [String] the scope identifier
      # @param var_name [String] the variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @return [TypeGuessr::Core::Types::Type, nil] the guessed type object or nil if not found
      def get_variable_type(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:)
        @mutex.synchronize do
          def_key = "#{def_line}:#{def_column}"
          @types.dig(scope_type, file_path, scope_id, var_name, def_key)
        end
      end

      def clear
        @mutex.synchronize do
          @index.each_value(&:clear)
          @types.each_value(&:clear)
          @call_assignments.each_value(&:clear)
        end
      end

      # Get total number of indexed variable definitions
      def size
        @mutex.synchronize do
          count = 0
          each_definition { |*, data| count += data.size }
          count
        end
      end

      # Find the variable type at a specific location (line number)
      # Searches for the closest type definition before the specified line
      # @param var_name [String] the variable name
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param max_line [Integer] the maximum line number (finds closest definition before this line)
      # @param scope_id [String] the scope identifier
      # @return [TypeGuessr::Core::Types::Type, nil] the guessed type object or nil if not found
      def find_variable_type_at_location(var_name:, scope_type:, max_line:, scope_id:)
        @mutex.synchronize do
          scope_types = @types[scope_type]
          return nil if !scope_types

          best_type = nil
          best_line = 0

          scope_types.each_value do |scopes|
            next if !scopes.key?(scope_id) || !scopes[scope_id].key?(var_name)

            scopes[scope_id][var_name].each do |def_key, type|
              line, _column = def_key.split(":").map(&:to_i)
              # Find closest definition before max_line
              if line <= max_line && line > best_line
                best_type = type
                best_line = line
              end
            end
          end

          best_type
        end
      end

      # Clear all index entries for a specific file
      # @param file_path [String] the file path to clear
      def clear_file(file_path)
        @mutex.synchronize do
          @index.each_value do |scope_index|
            scope_index.delete(file_path)
          end
          @types.each_value do |scope_types|
            scope_types.delete(file_path)
          end
          @call_assignments.each_value do |scope_types|
            scope_types.delete(file_path)
          end
        end
      end

      # Export index data as a hash (for debug inspection)
      # @return [Hash] the complete index data
      def to_h
        @mutex.synchronize do
          {
            index: deep_copy(@index),
            types: deep_copy(@types),
            call_assignments: deep_copy(@call_assignments)
          }
        end
      end

      # Get statistics about the index
      # @return [Hash] statistics about indexed data
      def stats
        @mutex.synchronize do
          files = Set.new
          local_count = 0
          instance_count = 0
          class_count = 0

          each_definition do |scope_type, file_path, _scope_id, _var_name, _def_key, data|
            files << file_path
            count = data.size
            case scope_type
            when :local_variables
              local_count += count
            when :instance_variables
              instance_count += count
            when :class_variables
              class_count += count
            end
          end

          {
            total_definitions: local_count + instance_count + class_count,
            files_count: files.size,
            local_variables_count: local_count,
            instance_variables_count: instance_count,
            class_variables_count: class_count
          }
        end
      end

      # Search index by file path pattern
      # @param query [String] the file path pattern to search for (case-insensitive)
      # @return [Hash] filtered index and types matching the query
      def search(query)
        @mutex.synchronize do
          query_downcase = query.downcase
          filtered_index = {}
          filtered_types = {}

          @index.each do |scope_type, scope_index|
            scope_index.each do |file_path, scopes|
              next if !file_path.downcase.include?(query_downcase)

              filtered_index[scope_type] ||= {}
              filtered_index[scope_type][file_path] = deep_copy(scopes)

              # Also include types for matching files
              if @types[scope_type]&.key?(file_path)
                filtered_types[scope_type] ||= {}
                filtered_types[scope_type][file_path] = deep_copy(@types[scope_type][file_path])
              end
            end
          end

          {
            index: filtered_index,
            types: filtered_types
          }
        end
      end

      private

      # Ensure nested hash structure exists for the given keys
      # @param root [Hash] the root hash to start from
      # @param keys [Array] the keys to traverse/create
      # @return [Hash] the final nested hash
      def ensure_nested_hash(root, *keys)
        current = root
        keys.each { |key| current = (current[key] ||= {}) }
        current
      end

      # Iterate over all definitions in the index
      # Yields scope_type, file_path, scope_id, var_name, def_key, and data for each definition
      # @yield [Symbol, String, String, String, String, Array<Hash>] scope_type, file_path, scope_id, var_name, def_key, data
      def each_definition
        @index.each do |scope_type, scope_index|
          scope_index.each do |file_path, scopes|
            scopes.each do |scope_id, vars|
              vars.each do |var_name, defs|
                defs.each do |def_key, data|
                  yield(scope_type, file_path, scope_id, var_name, def_key, data)
                end
              end
            end
          end
        end
      end

      # Deep copy a nested hash structure
      # @param obj [Object] the object to copy
      # @return [Object] deep copy of the object
      def deep_copy(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_copy(v) }
        when Array
          obj.map { |v| deep_copy(v) }
        else
          obj
        end
      end
    end
  end
end
