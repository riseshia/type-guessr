# frozen_string_literal: true

module TypeGuessr
  module Core
    module Index
      # Location-based index for finding IR nodes by file position
      # Provides O(log n) lookup from (file, line, column) to IR node
      class LocationIndex
        # Entry representing an indexed IR node with its location
        Entry = Data.define(:file_path, :line, :col_range, :node)

        def initialize
          # Hash of file_path => sorted array of entries
          # Entries are sorted by (line, col_range.begin) for binary search
          @index = {}
        end

        # Index an IR node at the given location
        # @param file_path [String] Absolute file path
        # @param node [TypeGuessr::Core::IR::Node] IR node to index
        def add(file_path, node)
          return unless node.loc

          @index[file_path] ||= []
          entry = Entry.new(
            file_path: file_path,
            line: node.loc.line,
            col_range: node.loc.col_range,
            node: node
          )
          @index[file_path] << entry
        end

        # Finalize indexing by sorting entries for binary search
        # Call this after all nodes have been added
        def finalize!
          @index.each_value do |entries|
            entries.sort_by! { |e| [e.line, e.col_range.begin] }
          end
        end

        # Find IR node at the given position
        # @param file_path [String, nil] Absolute file path (if nil, searches all files)
        # @param line [Integer] Line number (1-indexed)
        # @param column [Integer] Column number (0-indexed)
        # @return [TypeGuessr::Core::IR::Node, nil] IR node at position, or nil if not found
        def find(file_path, line, column)
          # If file_path is nil, search all files
          files_to_search = file_path ? [file_path] : @index.keys

          files_to_search.each do |path|
            entries = @index[path]
            next unless entries

            # Find all entries on the target line
            line_entries = entries.select { |e| e.line == line }
            next if line_entries.empty?

            # Find the most specific entry that contains the column
            # (smallest range that contains the position)
            matching_entries = line_entries.select do |e|
              e.col_range.cover?(column)
            end

            next if matching_entries.empty?

            # Return the entry with the smallest range (most specific)
            result = matching_entries.min_by { |e| e.col_range.size }&.node
            return result if result
          end

          nil
        end

        # Get all indexed nodes for a file
        # @param file_path [String] Absolute file path
        # @return [Array<TypeGuessr::Core::IR::Node>] All nodes in the file
        def nodes_for_file(file_path)
          entries = @index[file_path]
          return [] unless entries

          entries.map(&:node)
        end

        # Remove all entries for a file
        # @param file_path [String] Absolute file path
        def remove_file(file_path)
          @index.delete(file_path)
        end

        # Clear all indexed data
        def clear
          @index.clear
        end

        # Get statistics about the index
        # @return [Hash] Statistics hash
        def stats
          {
            files_count: @index.size,
            total_nodes: @index.values.sum(&:size)
          }
        end
      end
    end
  end
end
