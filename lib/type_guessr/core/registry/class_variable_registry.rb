# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves class variable write nodes
      # No inheritance chain traversal (class variables are class-scoped)
      class ClassVariableRegistry
        def initialize
          @variables = {} # { "ClassName" => { :@@name => WriteNode } }
          @file_entries = {} # { file_path => [[class_name, name], ...] }
        end

        # Register a class variable write
        # @param class_name [String] Class name
        # @param name [Symbol] Variable name (e.g., :@@count)
        # @param write_node [IR::ClassVariableWriteNode]
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

        # Look up a class variable write
        # @param class_name [String]
        # @param name [Symbol]
        # @return [IR::ClassVariableWriteNode, nil]
        def lookup(class_name, name)
          return nil unless class_name

          @variables.dig(class_name, name)
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
