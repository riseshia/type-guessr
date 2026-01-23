# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves instance/class variable write nodes
      # Supports inheritance chain traversal for instance variables when code_index is set
      class VariableRegistry
        # Adapter for getting class ancestors (must respond to #ancestors_of)
        # @return [#ancestors_of, nil] Adapter that returns array of ancestor names
        attr_accessor :code_index

        # @param code_index [#ancestors_of, nil] Adapter for inheritance lookup
        def initialize(code_index: nil)
          @instance_variables = {} # { "ClassName" => { :@name => WriteNode } }
          @class_variables = {}    # { "ClassName" => { :@@name => WriteNode } }
          @code_index = code_index
        end

        # Register an instance variable write
        # @param class_name [String] Class name
        # @param name [Symbol] Variable name (e.g., :@recipe)
        # @param write_node [IR::InstanceVariableWriteNode]
        def register_instance_variable(class_name, name, write_node)
          return unless class_name

          @instance_variables[class_name] ||= {}
          # First write wins (preserves consistent behavior)
          @instance_variables[class_name][name] ||= write_node
        end

        # Look up an instance variable write (with inheritance chain traversal)
        # @param class_name [String]
        # @param name [Symbol]
        # @return [IR::InstanceVariableWriteNode, nil]
        def lookup_instance_variable(class_name, name)
          return nil unless class_name

          # Try current class first
          result = @instance_variables.dig(class_name, name)
          return result if result

          # Traverse ancestor chain if code_index available
          return nil unless @code_index

          ancestors = @code_index.ancestors_of(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @instance_variables.dig(ancestor_name, name)
            return result if result
          end

          nil
        end

        # Register a class variable write
        # @param class_name [String]
        # @param name [Symbol] (e.g., :@@count)
        # @param write_node [IR::ClassVariableWriteNode]
        def register_class_variable(class_name, name, write_node)
          return unless class_name

          @class_variables[class_name] ||= {}
          # First write wins
          @class_variables[class_name][name] ||= write_node
        end

        # Look up a class variable write
        # @param class_name [String]
        # @param name [Symbol]
        # @return [IR::ClassVariableWriteNode, nil]
        def lookup_class_variable(class_name, name)
          return nil unless class_name

          @class_variables.dig(class_name, name)
        end

        # Clear all registered variables
        def clear
          @instance_variables.clear
          @class_variables.clear
        end
      end
    end
  end
end
