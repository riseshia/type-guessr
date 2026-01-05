# frozen_string_literal: true

module TypeGuessr
  module Core
    module IR
      # Location information for IR nodes
      # @param line [Integer] Line number (1-indexed)
      # @param col_range [Range] Column range
      Loc = Data.define(:line, :col_range)

      # Base class for all IR nodes
      # IR represents a reverse dependency graph where each node points to nodes it depends on
      class Node
        attr_reader :loc

        def initialize(loc:)
          @loc = loc
        end

        # Returns all nodes that this node directly depends on
        # @return [Array<Node>]
        def dependencies
          []
        end

        # Generate a unique hash for this node (type + identifier + line)
        # @return [String]
        def node_hash
          raise NotImplementedError, "#{self.class} must implement node_hash"
        end

        # Generate a unique key for this node (scope_id + node_hash)
        # @param scope_id [String] The scope identifier (e.g., "User#save")
        # @return [String]
        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Literal value node (leaf node with no dependencies)
      # @param type [TypeGuessr::Core::Types::Type] The type of the literal
      # @param loc [Loc] Location information
      #
      # Examples: "hello" → String, 123 → Integer, [] → Array, {} → Hash
      LiteralNode = Data.define(:type, :loc) do
        def dependencies
          []
        end

        def node_hash
          type_name = type.is_a?(Class) ? type.name.split("::").last : type.class.name.split("::").last
          "lit:#{type_name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Variable reference node
      # @param name [Symbol] Variable name
      # @param kind [Symbol] Variable kind (:local, :instance, :class)
      # @param dependency [Node] The node this variable depends on (assigned value)
      # @param called_methods [Array<Symbol>] Methods called on this variable (for duck typing)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is a shared array object that can be mutated during parsing
      VariableNode = Data.define(:name, :kind, :dependency, :called_methods, :loc) do
        def dependencies
          dependency ? [dependency] : []
        end

        def node_hash
          "var:#{name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Method parameter node
      # @param name [Symbol] Parameter name
      # @param kind [Symbol] Parameter kind (:required, :optional, :rest, :keyword_required,
      #                      :keyword_optional, :keyword_rest, :block, :forwarding)
      # @param default_value [Node, nil] Default value node (nil if no default)
      # @param called_methods [Array<Symbol>] Methods called on this parameter (for duck typing)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is a shared array object that can be mutated during parsing
      ParamNode = Data.define(:name, :kind, :default_value, :called_methods, :loc) do
        def dependencies
          default_value ? [default_value] : []
        end

        def node_hash
          "param:#{name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Constant reference node
      # @param name [String] Constant name (e.g., "DEFAULT_NAME", "User::ADMIN")
      # @param dependency [Node] The node where this constant is defined
      # @param loc [Loc] Location information
      ConstantNode = Data.define(:name, :dependency, :loc) do
        def dependencies
          dependency ? [dependency] : []
        end

        def node_hash
          "const:#{name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Method call node
      # @param method [Symbol] Method name
      # @param receiver [Node, nil] Receiver node (nil for implicit self)
      # @param args [Array<Node>] Argument nodes
      # @param block_params [Array<BlockParamSlot>] Block parameter slots
      # @param block_body [Node, nil] Block body return node (for inferring block return type)
      # @param has_block [Boolean] Whether a block was provided (even if empty)
      # @param loc [Loc] Location information
      CallNode = Data.define(:method, :receiver, :args, :block_params, :block_body, :has_block, :loc) do
        def dependencies
          deps = []
          deps << receiver if receiver
          deps.concat(args)
          deps << block_body if block_body
          deps
        end

        def node_hash
          "call:#{method}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Block parameter slot
      # Represents a parameter slot in a block (e.g., |user| in users.each { |user| ... })
      # @param index [Integer] Parameter index (0-based)
      # @param call_node [CallNode] The call node this slot belongs to
      # @param loc [Loc] Location information for the parameter itself
      BlockParamSlot = Data.define(:index, :call_node, :loc) do
        def dependencies
          [call_node]
        end

        def node_hash
          "bparam:#{index}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Branch merge node
      # Represents the convergence point of multiple branches (if/else, case/when, etc.)
      # The type is the union of all branch types
      # @param branches [Array<Node>] Final nodes from each branch
      # @param loc [Loc] Location information
      MergeNode = Data.define(:branches, :loc) do
        def dependencies
          branches
        end

        def node_hash
          "merge:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Method definition node
      # @param name [Symbol] Method name
      # @param params [Array<ParamNode>] Parameter nodes
      # @param return_node [Node] Node representing the return value
      # @param loc [Loc] Location information
      DefNode = Data.define(:name, :params, :return_node, :body_nodes, :loc) do
        def dependencies
          deps = params.dup
          deps << return_node if return_node
          deps.concat(body_nodes || [])
          deps
        end

        def node_hash
          "def:#{name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Class/Module node - container for methods and other definitions
      # @param name [String] Class or module name
      # @param methods [Array<DefNode>] Method definitions in this class/module
      # @param loc [Loc] Location information
      ClassModuleNode = Data.define(:name, :methods, :loc) do
        def dependencies
          methods
        end

        def node_hash
          "class:#{name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end

      # Self reference node
      # @param class_name [String] Name of the enclosing class/module
      # @param loc [Loc] Location information
      SelfNode = Data.define(:class_name, :loc) do
        def dependencies
          []
        end

        def node_hash
          "self:#{class_name}:#{loc&.line}"
        end

        def node_key(scope_id)
          "#{scope_id}:#{node_hash}"
        end
      end
    end
  end
end
