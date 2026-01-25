# frozen_string_literal: true

module TypeGuessr
  module Core
    module Index
      # Key-based index for finding IR nodes by scope and content
      # Provides O(1) lookup from node_key to IR node
      class LocationIndex
        def initialize
          # Hash of node_key => node for O(1) lookup
          @key_index = {}
          # Hash of file_path => [node_keys] for file removal
          @file_keys = {}
        end

        # Index an IR node with its scope_id
        # @param file_path [String] Absolute file path
        # @param node [TypeGuessr::Core::IR::Node] IR node to index
        # @param scope_id [String] Scope identifier (e.g., "User#save")
        def add(file_path, node, scope_id = "")
          return unless node.loc

          key = node.node_key(scope_id)
          @key_index[key] = node
          (@file_keys[file_path] ||= []) << key
        end

        # Finalize indexing (no-op, kept for API compatibility)
        def finalize!
          # No longer needed with key-based index
        end

        # Find IR node by its unique key
        # @param node_key [String] The node key (scope_id + node_hash)
        # @return [TypeGuessr::Core::IR::Node, nil] IR node or nil if not found
        def find_by_key(node_key)
          @key_index[node_key]
        end

        # Get all indexed nodes for a file
        # @param file_path [String] Absolute file path
        # @return [Array<TypeGuessr::Core::IR::Node>] All nodes in the file
        def nodes_for_file(file_path)
          keys = @file_keys[file_path] || []
          keys.filter_map { |k| @key_index[k] }
        end

        # Remove all entries for a file
        # @param file_path [String] Absolute file path
        def remove_file(file_path)
          @file_keys[file_path]&.each { |k| @key_index.delete(k) }
          @file_keys.delete(file_path)
        end

        # Clear all indexed data
        def clear
          @key_index.clear
          @file_keys.clear
        end

        # Get statistics about the index
        # @return [Hash] Statistics hash
        def stats
          {
            files_count: @file_keys.size,
            total_nodes: @key_index.size
          }
        end

        # Get all indexed file paths
        # @return [Array<String>] List of file paths
        def all_files
          @file_keys.keys
        end

        # Iterate over all indexed nodes with their scope IDs
        # @yield [node, scope_id] Block to execute for each node
        def each_node(&block)
          return enum_for(:each_node) unless block

          @key_index.each do |key, node|
            # Extract scope_id from "scope_id:node_hash" format
            scope_id = key.sub(/:#{Regexp.escape(node.node_hash)}$/, "")
            block.call(node, scope_id)
          end
        end

        # Find the scope ID for a node within a file
        # @param file_path [String] Absolute file path
        # @param node [TypeGuessr::Core::IR::Node] IR node to find
        # @return [String, nil] Scope ID or nil if not found
        def scope_for_node(file_path, node)
          keys = @file_keys[file_path] || []
          node_hash = node.node_hash
          matching_key = keys.find { |k| k.end_with?(":#{node_hash}") }
          return nil unless matching_key

          # Extract scope_id from "scope_id:node_hash" format
          matching_key.sub(/:#{Regexp.escape(node_hash)}$/, "")
        end
      end
    end
  end
end
