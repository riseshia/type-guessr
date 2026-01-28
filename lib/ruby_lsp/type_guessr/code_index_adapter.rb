# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Adapter wrapping RubyIndexer for Core layer consumption
    # Provides a stable interface isolating RubyIndexer API changes
    class CodeIndexAdapter
      def initialize(index)
        @index = index
      end

      # Find classes that define ALL given methods (intersection)
      # @param method_names [Array<Symbol>] Method names to search
      # @return [Array<String>] Class names defining all methods
      def find_classes_defining_methods(method_names)
        return [] if method_names.empty?
        return [] unless @index

        method_sets = method_names.map do |method_name|
          entries = @index.fuzzy_search(method_name.to_s) do |entry|
            entry.is_a?(RubyIndexer::Entry::Method) && entry.name == method_name.to_s
          end
          entries.filter_map do |entry|
            entry.owner.name if entry.respond_to?(:owner) && entry.owner
          end.uniq
        end

        return [] if method_sets.empty? || method_sets.any?(&:empty?)

        method_sets.reduce(:&) || []
      end

      # Get linearized ancestor chain for a class
      # @param class_name [String] Fully qualified class name
      # @return [Array<String>] Ancestor names in MRO order
      def ancestors_of(class_name)
        return [] unless @index

        @index.linearized_ancestors_of(class_name)
      rescue RubyIndexer::Index::NonExistingNamespaceError
        []
      end

      # Get kind of a constant
      # @param constant_name [String] Fully qualified constant name
      # @return [Symbol, nil] :class, :module, or nil
      def constant_kind(constant_name)
        return nil unless @index

        entries = @index[constant_name]
        return nil if entries.nil? || entries.empty?

        case entries.first
        when RubyIndexer::Entry::Class then :class
        when RubyIndexer::Entry::Module then :module
        end
      end

      # Look up owner of a class method
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [String, nil] Owner name or nil
      def class_method_owner(class_name, method_name)
        return nil unless @index

        unqualified_name = ::TypeGuessr::Core::IR.extract_last_name(class_name)
        singleton_name = "#{class_name}::<Class:#{unqualified_name}>"
        entries = @index.resolve_method(method_name, singleton_name)
        return nil if entries.nil? || entries.empty?

        entries.first.owner&.name
      rescue RubyIndexer::Index::NonExistingNamespaceError
        nil
      end
    end
  end
end
