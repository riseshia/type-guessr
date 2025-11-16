# frozen_string_literal: true

module RubyLsp
  module Guesser
    # Adapter to encapsulate access to RubyIndexer::Index internals
    # Provides a stable interface that isolates TypeMatcher from RubyIndexer's implementation details
    class RubyIndexAdapter
      def initialize(index)
        @index = index
      end

      # Get all class and module entries from the index
      # @return [Array<RubyIndexer::Entry::Class, RubyIndexer::Entry::Module>]
      def all_class_and_module_entries
        entries = []

        # Access the internal entries structure
        # This is the only place that knows about the internal implementation
        @index.instance_variable_get(:@entries).each_value do |entries_list|
          entries_list.each do |entry|
            entries << entry if class_or_module_entry?(entry)
          end
        end

        entries
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
