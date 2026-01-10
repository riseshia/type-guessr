# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves project method definitions
      # Supports inheritance chain traversal when ancestry_provider is set
      class MethodRegistry
        # Callback for getting class ancestors
        # @return [Proc, nil] A proc that takes class_name and returns array of ancestor names
        attr_accessor :ancestry_provider

        # @param ancestry_provider [Proc, nil] Returns ancestors for inheritance lookup
        def initialize(ancestry_provider: nil)
          @methods = {} # { "ClassName" => { "method_name" => DefNode } }
          @ancestry_provider = ancestry_provider
        end

        # Register a method definition
        # @param class_name [String] Class name (empty string for top-level)
        # @param method_name [String] Method name
        # @param def_node [IR::DefNode] Method definition node
        def register(class_name, method_name, def_node)
          @methods[class_name] ||= {}
          @methods[class_name][method_name] = def_node
        end

        # Look up a method definition (with inheritance chain traversal)
        # @param class_name [String] Class name
        # @param method_name [String] Method name
        # @return [IR::DefNode, nil] Method definition node or nil
        def lookup(class_name, method_name)
          # Try current class first
          result = @methods.dig(class_name, method_name)
          return result if result

          # Traverse ancestor chain if provider available
          return nil unless @ancestry_provider

          ancestors = @ancestry_provider.call(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @methods.dig(ancestor_name, method_name)
            return result if result
          end

          nil
        end

        # Get all registered class names
        # @return [Array<String>] List of class names (frozen)
        def registered_classes
          @methods.keys.freeze
        end

        # Get all methods for a specific class (direct methods only)
        # @param class_name [String] Class name
        # @return [Hash<String, IR::DefNode>] Methods hash (frozen)
        def methods_for_class(class_name)
          (@methods[class_name] || {}).freeze
        end

        # Search for methods matching a pattern
        # @param pattern [String] Search pattern (partial match on "ClassName#method_name")
        # @return [Array<Array>] Array of [class_name, method_name, def_node]
        def search(pattern)
          results = []
          @methods.each do |class_name, methods|
            methods.each do |method_name, def_node|
              full_name = "#{class_name}##{method_name}"
              results << [class_name, method_name, def_node] if full_name.include?(pattern)
            end
          end
          results
        end

        # Get all methods available on a class (including inherited)
        # @param class_name [String]
        # @return [Set<String>] Method names
        def all_methods_for_class(class_name)
          # Start with directly defined methods
          class_methods = (@methods[class_name]&.keys || []).to_set

          # Add inherited methods if ancestry_provider is available
          return class_methods unless @ancestry_provider

          ancestors = @ancestry_provider.call(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            ancestor_methods = @methods[ancestor_name]&.keys || []
            class_methods.merge(ancestor_methods)
          end

          class_methods
        end

        # Clear all registered methods
        def clear
          @methods.clear
        end
      end
    end
  end
end
