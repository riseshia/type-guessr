# frozen_string_literal: true

require "singleton"
require "set"

module TypeGuessr
  module Core
    # Thread-safe singleton index to store chains for variable definitions
    # Replaces VariableIndex with Chain-based storage
    class ChainIndex
      include Singleton

      def initialize
        @chains = {
          instance_variables: {},
          local_variables: {},
          class_variables: {}
        }
        @method_calls = {
          instance_variables: {},
          local_variables: {},
          class_variables: {}
        }
        @mutex = Mutex.new
      end

      # Store a chain for a variable definition
      # @param file_path [String]
      # @param scope_type [Symbol] :local_variables, :instance_variables, :class_variables
      # @param scope_id [String]
      # @param var_name [String]
      # @param def_line [Integer]
      # @param def_column [Integer]
      # @param chain [Chain] the expression chain
      def add_chain(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:, chain:)
        @mutex.synchronize do
          nested = ensure_nested_hash(@chains[scope_type], file_path, scope_id, var_name)
          def_key = "#{def_line}:#{def_column}"
          nested[def_key] = chain
        end
      end

      # Find chain at a specific location
      # Returns the closest chain definition before or at max_line
      # @param var_name [String]
      # @param scope_type [Symbol]
      # @param scope_id [String]
      # @param max_line [Integer]
      # @param file_path [String, nil] optional file path filter
      # @return [Chain, nil]
      def find_chain_at_location(var_name:, scope_type:, scope_id:, max_line:, file_path: nil)
        @mutex.synchronize do
          best_chain = nil
          best_line = 0

          scopes_hash = @chains[scope_type]
          return nil unless scopes_hash

          # If file_path specified, only search in that file
          files_to_search = file_path ? [file_path] : scopes_hash.keys

          files_to_search.each do |file|
            next unless scopes_hash[file]
            next unless scopes_hash[file][scope_id]
            next unless scopes_hash[file][scope_id][var_name]

            scopes_hash[file][scope_id][var_name].each do |def_key, chain|
              line, _column = def_key.split(":").map(&:to_i)
              if line <= max_line && line > best_line
                best_chain = chain
                best_line = line
              end
            end
          end

          best_chain
        end
      end

      # Store method calls for heuristic inference (backward compatibility)
      # @param file_path [String]
      # @param scope_type [Symbol]
      # @param scope_id [String]
      # @param var_name [String]
      # @param def_line [Integer]
      # @param def_column [Integer]
      # @param method_name [String]
      # @param call_line [Integer]
      # @param call_column [Integer]
      def add_method_call(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:,
                          method_name:, call_line:, call_column:)
        @mutex.synchronize do
          nested = ensure_nested_hash(@method_calls[scope_type], file_path, scope_id, var_name)
          def_key = "#{def_line}:#{def_column}"
          nested[def_key] ||= []

          call_info = { method: method_name, line: call_line, column: call_column }
          calls = nested[def_key]
          calls << call_info unless calls.include?(call_info)
        end
      end

      # Get method calls for a variable (for heuristic inference)
      # @param file_path [String]
      # @param scope_type [Symbol]
      # @param scope_id [String]
      # @param var_name [String]
      # @param def_line [Integer]
      # @param def_column [Integer]
      # @return [Array<Hash>]
      def get_method_calls(file_path:, scope_type:, scope_id:, var_name:, def_line:, def_column:)
        @mutex.synchronize do
          def_key = "#{def_line}:#{def_column}"
          @method_calls.dig(scope_type, file_path, scope_id, var_name, def_key) || []
        end
      end

      # Find all variable definitions matching criteria
      # @param var_name [String]
      # @param file_path [String, nil]
      # @param scope_type [Symbol]
      # @param scope_id [String]
      # @return [Array<Hash>]
      def find_definitions(var_name:, file_path: nil, scope_type:, scope_id:)
        @mutex.synchronize do
          definitions = []
          scopes_hash = @chains[scope_type]
          return definitions unless scopes_hash

          files_to_search = file_path ? [file_path] : scopes_hash.keys

          files_to_search.each do |file|
            next unless scopes_hash[file]
            next unless scopes_hash[file][scope_id]
            next unless scopes_hash[file][scope_id][var_name]

            scopes_hash[file][scope_id][var_name].each_key do |def_key|
              line, column = def_key.split(":").map(&:to_i)
              definitions << {
                file_path: file,
                scope_type: scope_type,
                scope_id: scope_id,
                var_name: var_name,
                def_line: line,
                def_column: column
              }
            end
          end

          definitions
        end
      end

      # Clear all data
      def clear
        @mutex.synchronize do
          @chains.each_value(&:clear)
          @method_calls.each_value(&:clear)
        end
      end

      # Clear data for a specific file
      # @param file_path [String]
      def clear_file(file_path)
        @mutex.synchronize do
          @chains.each_value { |scope| scope.delete(file_path) }
          @method_calls.each_value { |scope| scope.delete(file_path) }
        end
      end

      # Get statistics for debug server
      # @return [Hash]
      def stats
        @mutex.synchronize do
          total_definitions = 0
          files = Set.new
          local_vars = 0
          instance_vars = 0
          class_vars = 0

          @chains.each do |scope_type, scope_data|
            scope_data.each do |file_path, scopes|
              files.add(file_path)
              scopes.each_value do |vars|
                vars.each_value do |defs|
                  count = defs.size
                  total_definitions += count

                  case scope_type
                  when :local_variables
                    local_vars += count
                  when :instance_variables
                    instance_vars += count
                  when :class_variables
                    class_vars += count
                  end
                end
              end
            end
          end

          {
            total_definitions: total_definitions,
            files_count: files.size,
            local_variables_count: local_vars,
            instance_variables_count: instance_vars,
            class_variables_count: class_vars
          }
        end
      end

      # Search for chains by file path pattern
      # @param query [String] file path pattern to match
      # @return [Hash] filtered index and types
      def search(query)
        @mutex.synchronize do
          result_index = { instance_variables: {}, local_variables: {}, class_variables: {} }
          result_types = { instance_variables: {}, local_variables: {}, class_variables: {} }

          @chains.each do |scope_type, scope_data|
            scope_data.each do |file_path, scopes|
              next unless file_path.include?(query)

              result_index[scope_type][file_path] = scopes.transform_values do |vars|
                vars.transform_values do |defs|
                  # Convert Chain objects to simple hash for JSON serialization
                  defs.transform_values { |_chain| [] }  # Empty array for compatibility
                end
              end
            end
          end

          { index: result_index, types: result_types }
        end
      end

      private

      def ensure_nested_hash(root, *keys)
        current = root
        keys.each { |key| current = (current[key] ||= {}) }
        current
      end
    end
  end
end
