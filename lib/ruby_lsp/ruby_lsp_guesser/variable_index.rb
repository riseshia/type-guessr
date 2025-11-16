# frozen_string_literal: true

require "singleton"

module RubyLsp
  module Guesser
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
        @mutex = Mutex.new
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
          scope_index = @index[scope_type]
          scope_index[file_path] ||= {}
          scope_index[file_path][scope_id] ||= {}
          scope_index[file_path][scope_id][var_name] ||= {}

          def_key = "#{def_line}:#{def_column}"
          scope_index[file_path][scope_id][var_name][def_key] ||= []

          call_info = {
            method: method_name,
            line: call_line,
            column: call_column
          }

          calls = scope_index[file_path][scope_id][var_name][def_key]
          calls << call_info unless calls.include?(call_info)
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
                next unless vars.key?(var_name)

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
      # @param type [String] the inferred type (e.g., "String", "Integer", "User")
      def add_variable_type(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:, type:)
        @mutex.synchronize do
          scope_types = @types[scope_type]
          scope_types[file_path] ||= {}
          scope_types[file_path][scope_id] ||= {}
          scope_types[file_path][scope_id][var_name] ||= {}

          def_key = "#{def_line}:#{def_column}"
          scope_types[file_path][scope_id][var_name][def_key] = type
        end
      end

      # Get the type for a variable definition
      # @param file_path [String] the file path
      # @param scope_type [Symbol] :instance_variable, :local_variable, or :class_variable
      # @param scope_id [String] the scope identifier
      # @param var_name [String] the variable name
      # @param def_line [Integer] the line where the variable is defined
      # @param def_column [Integer] the column where the variable is defined
      # @return [String, nil] the inferred type or nil if not found
      def get_variable_type(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:)
        @mutex.synchronize do
          def_key = "#{def_line}:#{def_column}"
          @types.dig(scope_type, file_path, scope_id, var_name, def_key)
        end
      end

      # Clear all index data (useful for testing)
      def clear
        @mutex.synchronize do
          @index.each_value(&:clear)
          @types.each_value(&:clear)
        end
      end

      # Get total number of indexed variable definitions
      def size
        @mutex.synchronize do
          count = 0
          @index.each_value do |scope_index|
            scope_index.each_value do |scopes|
              scopes.each_value do |vars|
                vars.each_value do |defs|
                  count += defs.size
                end
              end
            end
          end
          count
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
        end
      end
    end
  end
end
