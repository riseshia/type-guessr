# frozen_string_literal: true

require "singleton"

module TypeGuessr
  module Core
    # Thread-safe singleton index to store constant alias mappings
    # Structure:
    # {
    #   file_path => {
    #     "MyApp::Types" => {
    #       target: "::TypeGuessr::Core::Types",
    #       line: 5,
    #       column: 2
    #     }
    #   }
    # }
    class ConstantIndex
      include Singleton

      # Maximum depth for recursive alias resolution to prevent infinite loops
      MAX_ALIAS_DEPTH = 5

      def initialize
        @aliases = {}
        @mutex = Mutex.new
      end

      # Add a constant alias mapping
      # @param file_path [String] the file path where the alias is defined
      # @param constant_fqn [String] the fully qualified constant name (e.g., "MyApp::Types")
      # @param target_fqn [String] the target constant FQN (e.g., "::TypeGuessr::Core::Types")
      # @param line [Integer] the line number where the alias is defined
      # @param column [Integer] the column number where the alias is defined
      def add_alias(file_path:, constant_fqn:, target_fqn:, line:, column:)
        @mutex.synchronize do
          @aliases[file_path] ||= {}
          @aliases[file_path][constant_fqn] = {
            target: target_fqn,
            line: line,
            column: column
          }
        end
      end

      # Resolve a constant alias to its target, recursively if needed
      # @param constant_fqn [String] the constant FQN to resolve
      # @return [String, nil] the resolved target FQN, or nil if not an alias
      def resolve_alias(constant_fqn)
        @mutex.synchronize do
          resolve_alias_internal(constant_fqn, depth: 0)
        end
      end

      # Clear all alias data for a specific file
      # @param file_path [String] the file path to clear
      def clear_file(file_path)
        @mutex.synchronize do
          @aliases.delete(file_path)
        end
      end

      # Clear all alias data (useful for testing)
      def clear
        @mutex.synchronize do
          @aliases.clear
        end
      end

      # Export alias data as a hash (for debug inspection)
      # @return [Hash] the complete alias data
      def to_h
        @mutex.synchronize do
          deep_copy(@aliases)
        end
      end

      # Get statistics about the index
      # @return [Hash] statistics about indexed aliases
      def stats
        @mutex.synchronize do
          files = @aliases.keys
          total_aliases = @aliases.values.sum(&:size)

          {
            total_aliases: total_aliases,
            files_count: files.size
          }
        end
      end

      private

      # Resolve a constant alias recursively (internal, assumes already synchronized)
      # @param constant_fqn [String] the constant FQN to resolve
      # @param depth [Integer] current recursion depth
      # @return [String, nil] the resolved target FQN, or nil if not an alias
      def resolve_alias_internal(constant_fqn, depth:)
        return nil if depth > MAX_ALIAS_DEPTH

        target = lookup_alias_no_sync(constant_fqn)
        return nil unless target

        # Recursively resolve if the target is also an alias
        further_resolved = resolve_alias_internal(target, depth: depth + 1)
        further_resolved || target
      end

      # Lookup an alias without recursion or synchronization (internal use only)
      # @param constant_fqn [String] the constant FQN
      # @return [String, nil] the target FQN or nil
      def lookup_alias_no_sync(constant_fqn)
        # Search across all files for the constant
        @aliases.each_value do |file_aliases|
          return file_aliases[constant_fqn][:target] if file_aliases.key?(constant_fqn)
        end

        nil
      end

      # Deep copy a nested hash structure
      # @param obj [Object] the object to copy
      # @return [Object] deep copy of the object
      def deep_copy(obj)
        case obj
        when Hash
          obj.transform_values { |v| deep_copy(v) }
        when Array
          obj.map { |v| deep_copy(v) }
        else
          obj
        end
      end
    end
  end
end
