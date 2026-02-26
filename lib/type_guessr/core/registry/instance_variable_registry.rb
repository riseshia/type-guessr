# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves instance variable write nodes
      # Supports inheritance chain traversal when code_index is set
      class InstanceVariableRegistry
        # Adapter for getting class ancestors (must respond to #ancestors_of)
        # @return [#ancestors_of, nil] Adapter that returns array of ancestor names
        attr_accessor :code_index

        # @param code_index [#ancestors_of, nil] Adapter for inheritance lookup
        def initialize(code_index: nil)
          @variables = {} # { "ClassName" => { :@name => WriteNode } }
          @file_entries = {} # { file_path => [[class_name, name], ...] }
          @code_index = code_index
        end

        # Register an instance variable write
        # @param class_name [String] Class name
        # @param name [Symbol] Variable name (e.g., :@recipe)
        # @param write_node [IR::InstanceVariableWriteNode]
        # @param file_path [String, nil] Source file path for tracking
        def register(class_name, name, write_node, file_path: nil)
          return unless class_name

          @variables[class_name] ||= {}
          return if @variables[class_name].key?(name) # first write wins

          @variables[class_name][name] = write_node

          return unless file_path

          @file_entries[file_path] ||= []
          @file_entries[file_path] << [class_name, name]
        end

        # Remove all entries registered from a specific file
        # @param file_path [String] Source file path
        def remove_file(file_path)
          entries = @file_entries.delete(file_path)
          return unless entries

          entries.each do |class_name, name|
            @variables[class_name]&.delete(name)
            @variables.delete(class_name) if @variables[class_name] && @variables[class_name].empty?
          end
        end

        # Look up an instance variable write (with inheritance chain traversal)
        # @param class_name [String]
        # @param name [Symbol]
        # @return [IR::InstanceVariableWriteNode, nil]
        def lookup(class_name, name)
          return nil unless class_name

          # Try current class first
          result = @variables.dig(class_name, name)
          return result if result

          # Traverse ancestor chain if code_index available
          return nil unless @code_index

          ancestors = @code_index.ancestors_of(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @variables.dig(ancestor_name, name)
            return result if result
          end

          nil
        end

        # Clear all registered variables
        def clear
          @variables.clear
          @file_entries.clear
        end
      end
    end
  end
end
