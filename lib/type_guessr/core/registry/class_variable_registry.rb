# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves class variable write nodes
      # No inheritance chain traversal (class variables are class-scoped)
      class ClassVariableRegistry
        def initialize
          @variables = {} # { "ClassName" => { :@@name => WriteNode } }
        end

        # Register a class variable write
        # @param class_name [String] Class name
        # @param name [Symbol] Variable name (e.g., :@@count)
        # @param write_node [IR::ClassVariableWriteNode]
        def register(class_name, name, write_node)
          return unless class_name

          @variables[class_name] ||= {}
          # First write wins
          @variables[class_name][name] ||= write_node
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
        end
      end
    end
  end
end
