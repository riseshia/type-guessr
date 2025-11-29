# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Adapter to encapsulate access to RubyIndexer::Index internals
    # Provides a stable interface that isolates TypeMatcher from RubyIndexer's implementation details
    # Implements the adapter interface required by TypeGuessr::Core::TypeMatcher
    class IndexAdapter
      def initialize(index)
        @index = index
      end

      # Get all class and module entries from the index
      # @return [Array<RubyIndexer::Entry::Class, RubyIndexer::Entry::Module>]
      def all_class_and_module_entries
        # Use fuzzy_search with nil query to get all entries, filtered by condition block
        @index.fuzzy_search(nil) do |entry|
          class_or_module_entry?(entry)
        end
      end

      # Resolve a method for a specific class/module name
      # @param method_name [String] the method name
      # @param class_name [String] the class/module name
      # @return [Array, nil] array of method entries or nil
      def resolve_method(method_name, class_name)
        @index.resolve_method(method_name, class_name)
      end

      private

      # Check if an entry is a class or module
      # @param entry [RubyIndexer::Entry] the entry to check
      # @return [Boolean]
      def class_or_module_entry?(entry)
        entry.is_a?(RubyIndexer::Entry::Class) || entry.is_a?(RubyIndexer::Entry::Module)
      end
    end
  end
end
