# frozen_string_literal: true

require_relative "../node_key_generator"

module TypeGuessr
  module Core
    # Intermediate Representation (IR) nodes for type inference.
    # Each node represents a construct in the source code and forms a
    # reverse dependency graph where nodes point to their dependencies.
    module IR
      # Shortcut to NodeKeyGenerator for generating node hash keys
      NodeKeyGenerator = Core::NodeKeyGenerator

      # Extract the last segment of a class/module path without array allocation.
      # Uses String#rindex instead of String#split to avoid creating intermediate arrays.
      # @param path [String] Class path (e.g., "Admin::User", "TypeGuessr::Core::IR::LiteralNode")
      # @return [String, nil] Last segment (e.g., "User", "LiteralNode"), the path itself if no "::", or nil if empty
      def self.extract_last_name(path)
        return nil if path.nil? || path.empty?

        last_sep = path.rindex("::")
        last_sep ? path[(last_sep + 2)..] : path
      end

      # Location information for IR nodes
      # @param offset [Integer] Byte offset from start of file (0-indexed)
      Loc = Data.define(:offset)

      # Method call signature for duck typing inference
      # @param name [Symbol] Method name
      # @param positional_count [Integer, nil] Number of positional arguments (nil if splat used)
      # @param keywords [Array<Symbol>] Keyword argument names
      CalledMethod = Data.define(:name, :positional_count, :keywords) do
        # String representation returns method name for logging/display
        def to_s
          name.to_s
        end
      end

      # Pretty print helper for IR nodes (Prism-style tree output)
      module TreeInspect
        BRANCH = "├── "
        LAST_BRANCH = "└── "
        PIPE = "│   "
        SPACE = "    "

        def tree_inspect(indent: "", last: true, root: false)
          lines = if root
                    ["@ #{IR.extract_last_name(self.class.name)} (location: #{format_loc})"]
                  else
                    prefix = last ? LAST_BRANCH : BRANCH
                    indent += (last ? SPACE : PIPE)
                    ["#{indent.delete_suffix(last ? SPACE : PIPE)}#{prefix}@ #{IR.extract_last_name(self.class.name)} (location: #{format_loc})"]
                  end
          lines.concat(tree_inspect_fields(indent))
          lines.join("\n")
        end

        private def format_loc
          loc ? "@#{loc.offset}" : "∅"
        end

        private def tree_field(name, value, indent, last: false)
          prefix = last ? LAST_BRANCH : BRANCH
          case value
          when nil
            "#{indent}#{prefix}#{name}: ∅"
          when Array
            if value.empty?
              "#{indent}#{prefix}#{name}: (length: 0)"
            else
              lines = ["#{indent}#{prefix}#{name}: (length: #{value.size})"]
              value.each_with_index do |item, idx|
                is_last = idx == value.size - 1
                item_indent = indent + (last ? SPACE : PIPE)
                if item.is_a?(TreeInspect)
                  lines << item.tree_inspect(indent: item_indent, last: is_last)
                else
                  item_prefix = is_last ? LAST_BRANCH : BRANCH
                  lines << "#{item_indent}#{item_prefix}#{item.inspect}"
                end
              end
              lines.join("\n")
            end
          when Symbol, String, Integer, TrueClass, FalseClass
            "#{indent}#{prefix}#{name}: #{value.inspect}"
          else
            if value.is_a?(TreeInspect)
              lines = ["#{indent}#{prefix}#{name}:"]
              child_indent = indent + (last ? SPACE : PIPE)
              lines << value.tree_inspect(indent: child_indent, last: true)
              lines.join("\n")
            else
              "#{indent}#{prefix}#{name}: #{value.inspect}"
            end
          end
        end

        private def tree_inspect_fields(_indent)
          []
        end
      end

      # Literal value node
      # @param type [TypeGuessr::Core::Types::Type] The type of the literal
      # @param literal_value [Object, nil] The actual literal value (for Symbol, Integer, String)
      # @param values [Array<Node>, nil] Internal value nodes for compound literals (Hash/Array)
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      #
      # Examples: "hello" → String, 123 → Integer, [] → Array, {} → Hash
      # For compound literals, values contains the internal expression nodes
      # For simple literals, literal_value stores the actual value (e.g., :a for symbols)
      LiteralNode = Data.define(:type, :literal_value, :values, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          values || []
        end

        def node_hash
          type_name = type.is_a?(Class) ? IR.extract_last_name(type.name) : IR.extract_last_name(type.class.name)
          NodeKeyGenerator.literal(type_name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          type_str = type.respond_to?(:name) ? type.name : IR.extract_last_name(type.class.name)
          [
            tree_field(:type, type_str, indent),
            tree_field(:literal_value, literal_value, indent),
            tree_field(:values, values, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Local variable write node (assignment)
      # @param name [Symbol] Variable name
      # @param value [Node] The node of the assigned value
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is a shared array object that can be mutated during parsing
      LocalWriteNode = Data.define(:name, :value, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          value ? [value] : []
        end

        def node_hash
          NodeKeyGenerator.local_write(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:value, value, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Local variable read node (reference)
      # @param name [Symbol] Variable name
      # @param write_node [LocalWriteNode, nil] The LocalWriteNode this read references
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is shared with LocalWriteNode for method-based inference propagation
      LocalReadNode = Data.define(:name, :write_node, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          write_node ? [write_node] : []
        end

        def node_hash
          NodeKeyGenerator.local_read(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:write_node, write_node, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Instance variable write node (@name = value)
      # @param name [Symbol] Variable name (e.g., :@recipe)
      # @param class_name [String, nil] Enclosing class name for deferred resolution
      # @param value [Node] The node of the assigned value
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      InstanceVariableWriteNode = Data.define(:name, :class_name, :value, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          value ? [value] : []
        end

        def node_hash
          NodeKeyGenerator.ivar_write(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:class_name, class_name, indent),
            tree_field(:value, value, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Instance variable read node (@name)
      # @param name [Symbol] Variable name (e.g., :@recipe)
      # @param class_name [String, nil] Enclosing class name for deferred resolution
      # @param write_node [InstanceVariableWriteNode, nil] The write node this read references
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      #
      # Note: write_node may be nil at conversion time if assignment appears later.
      # Resolver performs deferred lookup using class_name.
      InstanceVariableReadNode = Data.define(:name, :class_name, :write_node, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          write_node ? [write_node] : []
        end

        def node_hash
          NodeKeyGenerator.ivar_read(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:class_name, class_name, indent),
            tree_field(:write_node, write_node, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Class variable write node (@@name = value)
      # @param name [Symbol] Variable name (e.g., :@@count)
      # @param class_name [String, nil] Enclosing class name for deferred resolution
      # @param value [Node] The node of the assigned value
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      ClassVariableWriteNode = Data.define(:name, :class_name, :value, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          value ? [value] : []
        end

        def node_hash
          NodeKeyGenerator.cvar_write(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:class_name, class_name, indent),
            tree_field(:value, value, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Class variable read node (@@name)
      # @param name [Symbol] Variable name (e.g., :@@count)
      # @param class_name [String, nil] Enclosing class name for deferred resolution
      # @param write_node [ClassVariableWriteNode, nil] The write node this read references
      # @param called_methods [Array<Symbol>] Methods called on this variable (for method-based inference)
      # @param loc [Loc] Location information
      ClassVariableReadNode = Data.define(:name, :class_name, :write_node, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          write_node ? [write_node] : []
        end

        def node_hash
          NodeKeyGenerator.cvar_read(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:class_name, class_name, indent),
            tree_field(:write_node, write_node, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Method parameter node
      # @param name [Symbol] Parameter name
      # @param kind [Symbol] Parameter kind (:required, :optional, :rest, :keyword_required,
      #                      :keyword_optional, :keyword_rest, :block, :forwarding)
      # @param default_value [Node, nil] Default value node (nil if no default)
      # @param called_methods [Array<Symbol>] Methods called on this parameter (for method-based inference)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is a shared array object that can be mutated during parsing
      ParamNode = Data.define(:name, :kind, :default_value, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          default_value ? [default_value] : []
        end

        def node_hash
          NodeKeyGenerator.param(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:kind, kind, indent),
            tree_field(:default_value, default_value, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Constant reference node
      # @param name [String] Constant name (e.g., "DEFAULT_NAME", "User::ADMIN")
      # @param dependency [Node] The node where this constant is defined
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      ConstantNode = Data.define(:name, :dependency, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          dependency ? [dependency] : []
        end

        def node_hash
          NodeKeyGenerator.constant(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:dependency, dependency, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Method call node
      # @param method [Symbol] Method name
      # @param receiver [Node, nil] Receiver node (nil for implicit self)
      # @param args [Array<Node>] Argument nodes
      # @param block_params [Array<BlockParamSlot>] Block parameter slots
      # @param block_body [Node, nil] Block body return node (for inferring block return type)
      # @param has_block [Boolean] Whether a block was provided (even if empty)
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      CallNode = Data.define(:method, :receiver, :args, :block_params, :block_body, :has_block, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          deps = []
          deps << receiver if receiver
          deps.concat(args)
          deps << block_body if block_body
          deps
        end

        def node_hash
          NodeKeyGenerator.call(method, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:method, method, indent),
            tree_field(:receiver, receiver, indent),
            tree_field(:args, args, indent),
            tree_field(:block_params, block_params, indent),
            tree_field(:block_body, block_body, indent),
            tree_field(:has_block, has_block, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Block parameter slot
      # Represents a parameter slot in a block (e.g., |user| in users.each { |user| ... })
      # @param index [Integer] Parameter index (0-based)
      # @param call_node [CallNode] The call node this slot belongs to
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information for the parameter itself
      BlockParamSlot = Data.define(:index, :call_node, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          [call_node]
        end

        def node_hash
          NodeKeyGenerator.bparam(index, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:index, index, indent),
            tree_field(:call_node, "(CallNode ref)", indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Branch merge node
      # Represents the convergence point of multiple branches (if/else, case/when, etc.)
      # The type is the union of all branch types
      # @param branches [Array<Node>] Final nodes from each branch
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      MergeNode = Data.define(:branches, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          branches
        end

        def node_hash
          NodeKeyGenerator.merge(loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:branches, branches, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Short-circuit or node
      # Represents || and ||= operations where LHS is evaluated first,
      # and RHS is only evaluated if LHS is falsy (nil/false)
      # @param lhs [Node] Left-hand side (evaluated first)
      # @param rhs [Node] Right-hand side (evaluated only if LHS is falsy)
      # @param called_methods [Array<CalledMethod>] Methods called on this node
      # @param loc [Loc] Location information
      OrNode = Data.define(:lhs, :rhs, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          [lhs, rhs]
        end

        def node_hash
          NodeKeyGenerator.or_node(loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:lhs, lhs, indent),
            tree_field(:rhs, rhs, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Method definition node
      # @param name [Symbol] Method name
      # @param class_name [String, nil] Enclosing class name
      # @param params [Array<ParamNode>] Parameter nodes
      # @param return_node [Node] Node representing the return value
      # @param body_nodes [Array<Node>] All nodes in the method body
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      # @param singleton [Boolean] true if this is a singleton method (def self.method_name)
      DefNode = Data.define(:name, :class_name, :params, :return_node, :body_nodes, :called_methods, :loc, :singleton) do
        include TreeInspect

        def dependencies
          deps = params.dup
          deps << return_node if return_node
          deps.concat(body_nodes || [])
          deps
        end

        def node_hash
          NodeKeyGenerator.def_node(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:class_name, class_name, indent),
            tree_field(:params, params, indent),
            tree_field(:return_node, return_node, indent),
            tree_field(:body_nodes, body_nodes, indent),
            tree_field(:called_methods, called_methods, indent),
            tree_field(:singleton, singleton, indent, last: true),
          ]
        end
      end

      # Class/Module node - container for methods and other definitions
      # @param name [String] Class or module name
      # @param methods [Array<DefNode>] Method definitions in this class/module
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      ClassModuleNode = Data.define(:name, :methods, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          methods
        end

        def node_hash
          NodeKeyGenerator.class_module(name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:name, name, indent),
            tree_field(:methods, methods, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Self reference node
      # @param class_name [String] Name of the enclosing class/module
      # @param singleton [Boolean] Whether this self is in a singleton method context
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      SelfNode = Data.define(:class_name, :singleton, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          []
        end

        def node_hash
          NodeKeyGenerator.self_node(class_name, loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:class_name, class_name, indent),
            tree_field(:singleton, singleton, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end

      # Explicit return statement node
      # @param value [Node, nil] Return value node (nil for bare `return`)
      # @param called_methods [Array<CalledMethod>] Methods called on this node (for method-based inference)
      # @param loc [Loc] Location information
      ReturnNode = Data.define(:value, :called_methods, :loc) do
        include TreeInspect

        def dependencies
          value ? [value] : []
        end

        def node_hash
          NodeKeyGenerator.return_node(loc&.offset)
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end

        def tree_inspect_fields(indent)
          [
            tree_field(:value, value, indent),
            tree_field(:called_methods, called_methods, indent, last: true),
          ]
        end
      end
    end
  end
end
