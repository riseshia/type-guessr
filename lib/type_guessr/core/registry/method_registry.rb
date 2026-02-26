# frozen_string_literal: true

module TypeGuessr
  module Core
    module Registry
      # Stores and retrieves project method definitions
      # Supports inheritance chain traversal when code_index is set
      class MethodRegistry
        # Adapter for getting class ancestors (must respond to #ancestors_of)
        # @return [#ancestors_of, nil] Adapter that returns array of ancestor names
        attr_accessor :code_index

        # @param code_index [#ancestors_of, nil] Adapter for inheritance lookup
        def initialize(code_index: nil)
          @methods = {} # { "ClassName" => { "method_name" => DefNode } }
          @file_entries = {} # { file_path => [[class_name, method_name], ...] }
          @entry_sources = {} # { [class_name, method_name] => Set[file_path, ...] }
          @code_index = code_index
        end

        # Register a method definition
        # @param class_name [String] Class name (empty string for top-level)
        # @param method_name [String] Method name
        # @param def_node [IR::DefNode] Method definition node
        # @param file_path [String, nil] Source file path for tracking
        def register(class_name, method_name, def_node, file_path: nil)
          @methods[class_name] ||= {}
          @methods[class_name][method_name] = def_node

          return unless file_path

          @file_entries[file_path] ||= []
          @file_entries[file_path] << [class_name, method_name]
          key = [class_name, method_name]
          @entry_sources[key] ||= Set.new
          @entry_sources[key] << file_path
        end

        # Remove all method entries registered from a specific file
        # @param file_path [String] Source file path
        def remove_file(file_path)
          entries = @file_entries.delete(file_path)
          return unless entries

          entries.each do |class_name, method_name|
            key = [class_name, method_name]
            sources = @entry_sources[key]
            next unless sources

            sources.delete(file_path)
            next unless sources.empty?

            @entry_sources.delete(key)
            @methods[class_name]&.delete(method_name)
            @methods.delete(class_name) if @methods[class_name] && @methods[class_name].empty?
          end
        end

        # Look up a method definition (with inheritance chain traversal)
        # @param class_name [String] Class name
        # @param method_name [String] Method name
        # @return [IR::DefNode, nil] Method definition node or nil
        def lookup(class_name, method_name)
          # Try current class first
          result = @methods.dig(class_name, method_name)
          return result if result

          # Traverse ancestor chain if code_index available
          return nil unless @code_index

          ancestors = @code_index.ancestors_of(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @methods.dig(ancestor_name, method_name)
            return result if result
          end

          nil
        end

        # Get all methods for a specific class (direct methods only)
        # @param class_name [String] Class name
        # @return [Hash<String, IR::DefNode>] Methods hash (frozen)
        def methods_for_class(class_name)
          (@methods[class_name] || {}).freeze
        end

        # Iterate over all registered methods
        # @yield [class_name, method_name, def_node]
        def each_entry(&block)
          return enum_for(:each_entry) unless block

          @methods.each do |class_name, methods_hash|
            methods_hash.each do |method_name, def_node|
              block.call(class_name, method_name, def_node)
            end
          end
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

        # Clear all registered methods
        def clear
          @methods.clear
          @file_entries.clear
          @entry_sources.clear
        end
      end
    end
  end
end
