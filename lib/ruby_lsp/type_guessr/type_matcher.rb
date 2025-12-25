# frozen_string_literal: true

require_relative "index_adapter"

module RubyLsp
  module TypeGuessr
    # TypeMatcher finds classes/modules that have all the specified methods
    # Uses IndexAdapter to access the Ruby LSP index
    class TypeMatcher
      # Maximum number of matching types to return before truncating
      # This prevents performance issues when many types match
      MAX_MATCHING_TYPES = 3

      # Sentinel value indicating the results were truncated
      TRUNCATED_MARKER = "..."

      def initialize(index)
        @adapter = IndexAdapter.new(index)
      end

      # Given a set of method names, find all classes that have ALL those methods
      # Uses optimized lookup:
      # 1. Collect all owners (classes/modules where methods are defined)
      # 2. Filter to classes only (modules as fallback if no classes found)
      # 3. Filter candidates that have all specified methods (using resolve_method for inheritance/mixin chain)
      # 4. Reduce each candidate to its topmost ancestor that still has all methods
      # @param method_names [Array<String>] the method names to search for
      # @return [Array<String>] class names that have all the specified methods
      #   Returns up to MAX_MATCHING_TYPES results, with TRUNCATED_MARKER appended if more exist
      def find_matching_types(method_names)
        return [] if method_names.empty?

        # Step 1: Collect all owners from all methods
        all_owners = method_names.flat_map do |method_name|
          entries = @adapter.method_entries(method_name)
          entries.filter_map { |entry| entry.owner&.name }
        end.uniq

        return [] if all_owners.empty?

        # Step 2: Separate classes and modules
        class_owners = all_owners.select { |owner_name| class_entry?(owner_name) }
        module_owners = all_owners - class_owners

        # Step 3: Use classes as candidates, fallback to modules if no classes
        candidates = class_owners.empty? ? module_owners : class_owners

        # Step 4: Filter candidates that have ALL specified methods
        candidates.select! do |class_name|
          method_names.all? do |method_name|
            entries = @adapter.resolve_method(method_name, class_name)
            entries_present?(entries)
          end
        end

        # Step 5: Reduce each candidate to topmost ancestor with all methods
        candidates = candidates.map { |name| reduce_to_topmost_ancestor(name, method_names) }.uniq

        # Apply truncation if needed
        candidates = candidates.take(MAX_MATCHING_TYPES) + [TRUNCATED_MARKER] if candidates.size > MAX_MATCHING_TYPES

        candidates
      end

      # Check if the given name is a class (not a module)
      # @param name [String] the constant name to check
      # @return [Boolean] true if it's a class
      def class_entry?(name)
        !find_class_entry(name).nil?
      end

      # Get the first entry for a given constant name
      # Used to retrieve location information for linking
      # @param constant_name [String] the fully qualified constant name
      # @return [RubyIndexer::Entry, nil] the entry or nil if not found
      def get_entry(constant_name)
        entries = @adapter.resolve_constant(constant_name)
        entries.first
      end

      private

      # Find the first Class entry for a given constant name
      # @param constant_name [String] the constant name to search for
      # @return [RubyIndexer::Entry::Class, nil] the class entry or nil
      def find_class_entry(constant_name)
        @adapter.resolve_constant(constant_name).find { |e| e.is_a?(RubyIndexer::Entry::Class) }
      end

      # Check if entries array is present and not empty
      # @param entries [Array, nil] the entries to check
      # @return [Boolean] true if entries exist and are not empty
      def entries_present?(entries)
        !entries.nil? && !entries.empty?
      end

      # Reduce a class to its topmost ancestor that still has all specified methods
      # Walks up the inheritance chain until parent no longer has all methods
      # @param class_name [String] the starting class name
      # @param method_names [Array<String>] the methods that must be present
      # @return [String] the topmost ancestor class name with all methods
      def reduce_to_topmost_ancestor(class_name, method_names)
        current = class_name

        loop do
          entry = find_class_entry(current)
          break current unless entry

          parent = entry.parent_class
          # Stop if no parent, or parent is a core class (starts with ::)
          break current if parent.nil? || parent.start_with?("::")

          # Check if parent has all required methods
          parent_has_all = method_names.all? do |method_name|
            resolved = @adapter.resolve_method(method_name, parent)
            entries_present?(resolved)
          end

          break current unless parent_has_all

          current = parent
        end
      end
    end
  end
end
