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
      # Uses optimized lookup: gets candidates from first method, then filters by remaining methods
      # @param method_names [Array<String>] the method names to search for
      # @return [Array<String>] class names that have all the specified methods
      #   Returns up to MAX_MATCHING_TYPES results, with TRUNCATED_MARKER appended if more exist
      def find_matching_types(method_names)
        return [] if method_names.empty?

        # Get candidate classes from first method (direct index lookup - fast!)
        first_method = method_names.first
        method_entries = @adapter.method_entries(first_method)
        return [] if method_entries.empty?

        # Extract owner class names from method entries
        candidates = method_entries.filter_map { |entry| entry.owner&.name }.uniq
        return [] if candidates.empty?

        # Filter candidates by remaining methods
        remaining_methods = method_names.drop(1)
        remaining_methods.each do |method_name|
          candidates.select! do |class_name|
            entries = @adapter.resolve_method(method_name, class_name)
            !entries.nil? && !entries.empty?
          end
          break if candidates.empty?
        end

        # Apply truncation if needed
        candidates = candidates.take(MAX_MATCHING_TYPES) + [TRUNCATED_MARKER] if candidates.size > MAX_MATCHING_TYPES

        candidates
      end

      # Get the first entry for a given constant name
      # Used to retrieve location information for linking
      # @param constant_name [String] the fully qualified constant name
      # @return [RubyIndexer::Entry, nil] the entry or nil if not found
      def get_entry(constant_name)
        entries = @adapter.resolve_constant(constant_name)
        entries.first
      end
    end
  end
end
