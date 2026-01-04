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
      end

      # Method parameter node
      # @param name [Symbol] Parameter name
      # @param default_value [Node, nil] Default value node (nil if no default)
      # @param called_methods [Array<Symbol>] Methods called on this parameter (for duck typing)
      # @param loc [Loc] Location information
      #
      # Note: called_methods is a shared array object that can be mutated during parsing
      ParamNode = Data.define(:name, :default_value, :called_methods, :loc) do
        def dependencies
          default_value ? [default_value] : []
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
      end

      # Method call node
      # @param method [Symbol] Method name
      # @param receiver [Node, nil] Receiver node (nil for implicit self)
      # @param args [Array<Node>] Argument nodes
      # @param block_params [Array<BlockParamSlot>] Block parameter slots
      # @param loc [Loc] Location information
      CallNode = Data.define(:method, :receiver, :args, :block_params, :loc) do
        def dependencies
          deps = []
          deps << receiver if receiver
          deps.concat(args)
          deps
        end
      end

      # Block parameter slot
      # Represents a parameter slot in a block (e.g., |user| in users.each { |user| ... })
      # @param index [Integer] Parameter index (0-based)
      # @param call_node [CallNode] The call node this slot belongs to
      BlockParamSlot = Data.define(:index, :call_node) do
        def dependencies
          [call_node]
        end

        def loc
          call_node.loc
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
      end

      # Method definition node
      # @param name [Symbol] Method name
      # @param params [Array<ParamNode>] Parameter nodes
      # @param return_node [Node] Node representing the return value
      # @param loc [Loc] Location information
      DefNode = Data.define(:name, :params, :return_node, :loc) do
        def dependencies
          deps = params.dup
          deps << return_node if return_node
          deps
        end
      end
    end
  end
end
