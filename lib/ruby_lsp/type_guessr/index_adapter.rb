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

      # Resolve a method for a specific class/module name
      # @param method_name [String] the method name
      # @param class_name [String] the class/module name
      # @return [Array, nil] array of method entries or nil
      def resolve_method(method_name, class_name)
        @index.resolve_method(method_name, class_name)
      end

      # Get all method entries with the given name from the index
      # This uses direct index access for efficient lookup
      # @param method_name [String] the method name to search for
      # @return [Array<RubyIndexer::Entry::Method>] array of method entries
      def method_entries(method_name)
        @index[method_name] || []
      end

      # Resolve a constant (class/module) by name
      # @param constant_name [String] the fully qualified constant name
      # @return [Array<RubyIndexer::Entry>] array of entries or empty array
      def resolve_constant(constant_name)
        @index[constant_name] || []
      end
    end
  end
end
