# frozen_string_literal: true

module TypeGuessr
  module Core
    # TypeDB stores inferred types for expressions and symbols
    # Provides 2-layer lookup: (file, range) → ref → Type
    class TypeDB
      def initialize
        # file_path => { range_key => type }
        @store = Hash.new { |h, k| h[k] = {} }
      end

      # Store a type for a given file and range
      # @param file_path [String] the file path
      # @param range [Hash] the range with :start and :end
      # @param type [TypeGuessr::Core::Types::Type] the type to store
      def set_type(file_path, range, type)
        range_key = normalize_range(range)
        @store[file_path][range_key] = type
      end

      # Retrieve a type for a given file and range
      # @param file_path [String] the file path
      # @param range [Hash] the range with :start and :end
      # @return [TypeGuessr::Core::Types::Type, nil] the stored type or nil
      def get_type(file_path, range)
        range_key = normalize_range(range)
        @store[file_path][range_key]
      end

      # Clear all types for a specific file
      # @param file_path [String] the file path to clear
      def clear_file(file_path)
        @store.delete(file_path)
      end

      # Clear all stored types
      def clear
        @store.clear
      end

      private

      # Normalize range to a comparable key
      # @param range [Hash] the range with :start and :end
      # @return [String] normalized range key
      def normalize_range(range)
        start_pos = range[:start]
        end_pos = range[:end]
        "#{start_pos[:line]}:#{start_pos[:character]}-#{end_pos[:line]}:#{end_pos[:character]}"
      end
    end
  end
end
