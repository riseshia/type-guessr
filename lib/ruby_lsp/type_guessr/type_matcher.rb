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
      # @param method_names [Array<String>] the method names to search for
      # @return [Array<String>] class names that have all the specified methods
      #   Returns up to MAX_MATCHING_TYPES results, with TRUNCATED_MARKER appended if more exist
      def find_matching_types(method_names)
        return [] if method_names.empty?

        # Get all class/module entries from the index through the adapter
        all_entries = @adapter.all_class_and_module_entries

        # Find classes that have all the specified methods
        matching_classes = []
        all_entries.each do |class_entry|
          class_name = class_entry.name
          has_all_methods = method_names.all? do |method_name|
            method_entries = @adapter.resolve_method(method_name, class_name)
            !method_entries.nil? && !method_entries.empty?
          end

          next unless has_all_methods

          matching_classes << class_name

          # Early termination: stop searching if we found too many matches
          next unless matching_classes.size > MAX_MATCHING_TYPES

          matching_classes[MAX_MATCHING_TYPES] = TRUNCATED_MARKER
          break
        end

        matching_classes
      end
    end
  end
end
