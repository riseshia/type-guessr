# frozen_string_literal: true

require_relative "../../type_guessr/core/type_formatter"

module RubyLsp
  module TypeGuessr
    # Builds graph data from IR nodes for visualization
    # Traverses the dependency DAG and serializes to JSON format for mermaid.js
    class GraphBuilder
      def initialize(runtime_adapter)
        @runtime_adapter = runtime_adapter
      end

      # Build graph data starting from a node key
      # @param node_key [String] The starting node key (e.g., "User#save:def:save:10")
      # @return [Hash, nil] Graph data with nodes and edges, or nil if node not found
      def build(node_key)
        root_node = @runtime_adapter.find_node_by_key(node_key)
        return nil unless root_node

        nodes = {}
        edges = []
        visited = Set.new

        traverse(root_node, node_key, nodes, edges, visited)

        result = {
          nodes: nodes.values,
          edges: edges,
          root_key: node_key
        }

        # Add DefNode tree_inspect for debugging
        result[:def_node_inspect] = root_node.tree_inspect(root: true) if root_node.is_a?(::TypeGuessr::Core::IR::DefNode)

        result
      end

      # Limit to MAX_NODES to prevent infinite/huge graphs
      MAX_NODES = 200

      private

      # BFS traversal of the dependency graph
      def traverse(node, node_key, nodes, edges, visited)
        queue = [[node, node_key]]

        while (current, current_key = queue.shift)
          next if visited.include?(current_key)
          break if visited.size >= MAX_NODES

          visited.add(current_key)
          nodes[current_key] = serialize_node(current, current_key)

          # Get arg_keys for CallNode to skip redundant subgraph internal edges
          arg_keys = if current.is_a?(::TypeGuessr::Core::IR::CallNode)
                       current.args.compact.map { |arg| infer_dependency_key(arg, current_key, current) }
                     else
                       []
                     end

          # Traverse dependencies
          current.dependencies.each do |dep_node|
            next unless dep_node

            dep_key = infer_dependency_key(dep_node, current_key, current)

            # Skip edges to arguments that are inside the CallNode's subgraph
            # These are visually redundant since the argument is already shown inside the subgraph
            edges << { from: current_key, to: dep_key } unless arg_keys.include?(dep_key)

            queue << [dep_node, dep_key]
          end
        end

        warn("[GraphBuilder] Traversal complete: #{visited.size} nodes") if Config.debug?
      end

      # Serialize a node to hash format
      def serialize_node(node, node_key)
        warn("[GraphBuilder] serialize_node: #{node_key}") if Config.debug?
        result = @runtime_adapter.infer_type(node)
        warn("[GraphBuilder] infer_type done for: #{node_key}") if Config.debug?

        {
          key: node_key,
          type: node_type_name(node),
          line: node.loc&.line,
          inferred_type: ::TypeGuessr::Core::TypeFormatter.format(result.type),
          details: extract_details(node, node_key)
        }
      end

      # Get the short type name for a node
      def node_type_name(node)
        node.class.name.split("::").last
      end

      # Extract details based on node type
      def extract_details(node, node_key)
        case node
        when ::TypeGuessr::Core::IR::DefNode
          # Build full method signature with param types
          param_signatures = (node.params || []).map do |p|
            type_result = @runtime_adapter.infer_type(p)
            type_str = ::TypeGuessr::Core::TypeFormatter.format(type_result.type)
            "#{p.name}: #{type_str}"
          end
          { name: node.name.to_s, param_signatures: param_signatures }
        when ::TypeGuessr::Core::IR::CallNode
          # Calculate arg keys for subgraph grouping
          arg_keys = node.args.compact.map do |arg|
            infer_dependency_key(arg, node_key, node)
          end
          # Get receiver description
          receiver_str = format_receiver(node.receiver)
          { method: node.method.to_s, has_block: node.has_block, arg_keys: arg_keys, receiver: receiver_str }
        when ::TypeGuessr::Core::IR::WriteNode
          { name: node.name.to_s, kind: node.kind.to_s, called_methods: node.called_methods.map(&:to_s),
            is_read: false }
        when ::TypeGuessr::Core::IR::ReadNode
          { name: node.name.to_s, kind: node.kind.to_s, called_methods: node.called_methods.map(&:to_s),
            is_read: true }
        when ::TypeGuessr::Core::IR::ParamNode
          { name: node.name.to_s, kind: node.kind.to_s, called_methods: node.called_methods.map(&:to_s) }
        when ::TypeGuessr::Core::IR::LiteralNode
          { literal_type: ::TypeGuessr::Core::TypeFormatter.format(node.type) }
        when ::TypeGuessr::Core::IR::MergeNode
          { branches_count: node.branches.size }
        when ::TypeGuessr::Core::IR::ConstantNode
          { name: node.name.to_s }
        when ::TypeGuessr::Core::IR::BlockParamSlot
          { index: node.index }
        when ::TypeGuessr::Core::IR::SelfNode
          { class_name: node.class_name.to_s }
        when ::TypeGuessr::Core::IR::ClassModuleNode
          { name: node.name.to_s, methods_count: node.methods&.size || 0 }
        else
          {}
        end
      end

      # Format receiver node for display
      def format_receiver(receiver)
        return nil unless receiver

        case receiver
        when ::TypeGuessr::Core::IR::SelfNode
          "self"
        when ::TypeGuessr::Core::IR::WriteNode, ::TypeGuessr::Core::IR::ReadNode
          receiver.name.to_s
        when ::TypeGuessr::Core::IR::ConstantNode
          receiver.name.to_s
        when ::TypeGuessr::Core::IR::CallNode
          ".#{receiver.method}"
        end
      end

      # Infer node key for a dependency
      # Uses parent node info to determine correct scope for children
      def infer_dependency_key(dep_node, parent_key, parent_node = nil)
        # Extract scope_id from parent key
        # Key format: {scope_id}:{type}:{name}:{line}
        # scope_id can contain :: for namespaces and # for methods
        # node_hash is always the last 3 colon-separated parts
        parts = parent_key.split(":")
        # The node_hash is "type:name:line" (3 parts)
        scope_id = parts.size > 3 ? parts[0...-3].join(":") : parts[0]

        # For DefNode parents, children have a deeper scope (Class#method)
        if parent_node.is_a?(::TypeGuessr::Core::IR::DefNode)
          method_name = parent_node.name
          scope_id = scope_id.empty? ? "##{method_name}" : "#{scope_id}##{method_name}"
        end

        dep_node.node_key(scope_id)
      end
    end
  end
end
