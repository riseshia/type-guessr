# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Builds graph data from IR nodes for visualization
    # Uses body_nodes structure with value/receiver/args edges
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

        @nodes = {}
        @edges = []
        @scope_id = extract_scope_id(node_key)

        if root_node.is_a?(::TypeGuessr::Core::IR::DefNode)
          build_def_node_graph(root_node, node_key)
        else
          # Fallback for non-DefNode: use BFS with dependencies
          traverse_dependencies(root_node, node_key)
        end

        result = {
          nodes: @nodes.values,
          edges: @edges,
          root_key: node_key
        }

        result[:def_node_inspect] = root_node.tree_inspect(root: true) if root_node.is_a?(::TypeGuessr::Core::IR::DefNode)

        result
      end

      # Limit to MAX_NODES to prevent infinite/huge graphs
      MAX_NODES = 200

      private

      def build_def_node_graph(def_node, def_key)
        method_scope = @scope_id.empty? ? "##{def_node.name}" : "#{@scope_id}##{def_node.name}"

        # 1. Add DefNode
        add_node(def_node, @scope_id)

        # 2. Add params and connect to DefNode
        def_node.params&.each do |param|
          param_key = add_node(param, method_scope)
          add_edge(param_key, def_key)
        end

        # 3. Process body_nodes - collect all nodes and create edges based on value/receiver/args
        return_sources = []
        last_body_key = nil
        def_node.body_nodes&.each do |body_node|
          last_body_key = process_body_node(body_node, method_scope, return_sources)
        end

        # Add last expression as implicit return (if not already a ReturnNode)
        return_sources << last_body_key if last_body_key && !return_sources.include?(last_body_key)

        # 4. Create virtual Return node and connect return sources
        return unless return_sources.any?

        return_key = "#{method_scope}:return:virtual"
        @nodes[return_key] = {
          key: return_key,
          type: "Return",
          line: def_node.loc&.line,
          inferred_type: infer_type_str(def_node),
          details: { virtual: true }
        }

        return_sources.each do |source_key|
          add_edge(source_key, return_key)
        end

        add_edge(return_key, def_key)
      end

      def process_body_node(node, scope_id, return_sources)
        return unless node
        return if @nodes.size >= MAX_NODES

        node_key = add_node(node, scope_id)

        # Track return sources
        return_sources << node_key if node.is_a?(::TypeGuessr::Core::IR::ReturnNode)

        # Create edges based on node structure (value, receiver, args)
        case node
        when ::TypeGuessr::Core::IR::LocalWriteNode,
             ::TypeGuessr::Core::IR::InstanceVariableWriteNode,
             ::TypeGuessr::Core::IR::ClassVariableWriteNode
          if node.value
            value_key = process_body_node(node.value, scope_id, return_sources)
            add_edge(value_key, node_key) if value_key
          end
        when ::TypeGuessr::Core::IR::CallNode
          if node.receiver
            receiver_key = process_body_node(node.receiver, scope_id, return_sources)
            add_edge(receiver_key, node_key) if receiver_key
          end
          node.args&.each do |arg|
            next unless arg

            arg_key = process_body_node(arg, scope_id, return_sources)
            add_edge(arg_key, node_key) if arg_key
          end
        when ::TypeGuessr::Core::IR::ReturnNode
          if node.value
            value_key = process_body_node(node.value, scope_id, return_sources)
            add_edge(value_key, node_key) if value_key
          end
        when ::TypeGuessr::Core::IR::LocalReadNode
          # LocalReadNode references its write_node (variable definition)
          if node.write_node
            write_key = process_body_node(node.write_node, scope_id, return_sources)
            add_edge(write_key, node_key) if write_key
          end
        when ::TypeGuessr::Core::IR::InstanceVariableReadNode,
             ::TypeGuessr::Core::IR::ClassVariableReadNode
          # Instance/class variable reads may reference writes in other methods
          # We don't follow these edges in the graph to avoid complexity
          nil
        when ::TypeGuessr::Core::IR::ParamNode
          # ParamNode is a leaf node, no edges to create
          nil
        when ::TypeGuessr::Core::IR::MergeNode
          node.branches&.each do |branch|
            branch_key = process_body_node(branch, scope_id, return_sources)
            add_edge(branch_key, node_key) if branch_key
          end
        when ::TypeGuessr::Core::IR::LiteralNode
          # Process internal values (for Hash/Array literals with expressions) # -- values is an Array attribute, not Hash#values
          node.values&.each do |value_node|
            value_key = process_body_node(value_node, scope_id, return_sources)
            add_edge(value_key, node_key) if value_key
          end
          # rubocop:enable Style/HashEachMethods
        end

        node_key
      end

      def add_node(node, scope_id = @scope_id)
        node_key = node.node_key(scope_id)
        return node_key if @nodes.key?(node_key)

        @nodes[node_key] = serialize_node(node, node_key)
        node_key
      end

      def add_edge(from_key, to_key)
        return unless from_key && to_key

        edge = { from: from_key, to: to_key }
        @edges << edge unless @edges.include?(edge)
      end

      def infer_type_str(node)
        result = @runtime_adapter.infer_type(node)
        result.type.to_s
      end

      # BFS traversal for non-DefNode (fallback)
      def traverse_dependencies(node, node_key)
        visited = Set.new
        queue = [[node, node_key]]

        while (current, current_key = queue.shift)
          next if visited.include?(current_key)
          break if visited.size >= MAX_NODES

          visited.add(current_key)
          add_node(current, @scope_id)

          current.dependencies.each do |dep_node|
            next unless dep_node

            dep_key = dep_node.node_key(@scope_id)
            add_edge(current_key, dep_key)
            queue << [dep_node, dep_key]
          end
        end
      end

      # Extract scope_id from a node key
      # Key format: {scope_id}:{type}:{name}:{line}
      def extract_scope_id(node_key)
        # For root key like "Class:def:name:line", scope is "Class"
        # For "Class#method:type:name:line", scope is "Class#method"
        # Find the last occurrence of known type prefixes
        type_prefixes = %w[def: param: call: lit: local_write: local_read: ivar_write: ivar_read: cvar_write: cvar_read: merge: const: bparam: return: class:
                           self:]
        last_type_pos = nil

        type_prefixes.each do |prefix|
          pos = node_key.rindex(":#{prefix}")
          pos = node_key.index(prefix) if pos.nil? && node_key.start_with?(prefix)
          next unless pos

          pos += 1 if node_key[pos] == ":"
          last_type_pos = pos if last_type_pos.nil? || pos > last_type_pos
        end

        if last_type_pos
          node_key[0...(last_type_pos - 1)]
        else
          # Fallback for unknown type prefixes: count colons (format: scope:type:name:line)
          colon_positions = []
          node_key.each_char.with_index { |c, i| colon_positions << i if c == ":" }

          if colon_positions.size >= 3
            node_key[0...colon_positions[-3]]
          else
            node_key.split(":").first || ""
          end
        end
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
          inferred_type: result.type.to_s,
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
            type_str = type_result.type.to_s
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
        when ::TypeGuessr::Core::IR::LocalWriteNode
          { name: node.name.to_s, kind: "local", called_methods: node.called_methods.map(&:to_s),
            is_read: false }
        when ::TypeGuessr::Core::IR::LocalReadNode
          { name: node.name.to_s, kind: "local", called_methods: node.called_methods.map(&:to_s),
            is_read: true }
        when ::TypeGuessr::Core::IR::InstanceVariableWriteNode
          { name: node.name.to_s, kind: "instance", class_name: node.class_name,
            called_methods: node.called_methods.map(&:to_s), is_read: false }
        when ::TypeGuessr::Core::IR::InstanceVariableReadNode
          { name: node.name.to_s, kind: "instance", class_name: node.class_name,
            called_methods: node.called_methods.map(&:to_s), is_read: true }
        when ::TypeGuessr::Core::IR::ClassVariableWriteNode
          { name: node.name.to_s, kind: "class", class_name: node.class_name,
            called_methods: node.called_methods.map(&:to_s), is_read: false }
        when ::TypeGuessr::Core::IR::ClassVariableReadNode
          { name: node.name.to_s, kind: "class", class_name: node.class_name,
            called_methods: node.called_methods.map(&:to_s), is_read: true }
        when ::TypeGuessr::Core::IR::ParamNode
          { name: node.name.to_s, kind: node.kind.to_s, called_methods: node.called_methods.map(&:to_s) }
        when ::TypeGuessr::Core::IR::LiteralNode
          { literal_type: node.type.to_s }
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
        when ::TypeGuessr::Core::IR::LocalWriteNode, ::TypeGuessr::Core::IR::LocalReadNode,
             ::TypeGuessr::Core::IR::InstanceVariableWriteNode, ::TypeGuessr::Core::IR::InstanceVariableReadNode,
             ::TypeGuessr::Core::IR::ClassVariableWriteNode, ::TypeGuessr::Core::IR::ClassVariableReadNode
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
        # Find the scope by locating the last 3 colons (for type:name:line)
        colon_positions = []
        parent_key.each_char.with_index { |c, i| colon_positions << i if c == ":" }

        scope_id = if colon_positions.size >= 3
                     # Take everything before the 3rd-to-last colon
                     parent_key[0...colon_positions[-3]]
                   else
                     parent_key.split(":").first
                   end

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
