# frozen_string_literal: true

require "prism"
require_relative "../ir/nodes"
require_relative "../types"

module TypeGuessr
  module Core
    module Converter
      # Converts Prism AST to IR graph (reverse dependency graph)
      # Each IR node points to nodes it depends on
      class PrismConverter
        # Context for tracking variable bindings during conversion
        class Context
          attr_reader :variables
          attr_accessor :current_class, :current_method

          def initialize(parent = nil)
            @parent = parent
            @variables = {} # name => node
            @instance_variables = {} # @name => node (only for class-level context)
            @constants = {} # name => dependency node (for constant alias tracking)
            @scope_type = nil # :class, :method, :block, :top_level
            @current_class = nil
            @current_method = nil
          end

          def register_variable(name, node)
            @variables[name] = node
          end

          def lookup_variable(name)
            @variables[name] || @parent&.lookup_variable(name)
          end

          # Register an instance variable at the class level
          # Instance variables are shared across all methods in a class
          def register_instance_variable(name, node)
            if @scope_type == :class
              @instance_variables[name] = node
            elsif @parent
              @parent.register_instance_variable(name, node)
            else
              # Top-level instance variable, store locally
              @instance_variables[name] = node
            end
          end

          # Lookup an instance variable from the class level
          def lookup_instance_variable(name)
            if @scope_type == :class
              @instance_variables[name]
            elsif @parent
              @parent.lookup_instance_variable(name)
            else
              @instance_variables[name]
            end
          end

          # Register a constant's dependency node for alias tracking
          def register_constant(name, dependency_node)
            @constants[name] = dependency_node
          end

          # Lookup a constant's dependency node (for alias resolution)
          def lookup_constant(name)
            @constants[name] || @parent&.lookup_constant(name)
          end

          def fork(scope_type)
            child = Context.new(self)
            child.instance_variable_set(:@scope_type, scope_type)
            child.current_class = current_class_name
            child.current_method = current_method_name
            child
          end

          def scope_type
            @scope_type || @parent&.scope_type
          end

          # Get the current class name (from this context or parent)
          def current_class_name
            @current_class || @parent&.current_class_name
          end

          # Get the current method name (from this context or parent)
          def current_method_name
            @current_method || @parent&.current_method_name
          end

          # Generate scope_id for node lookup (e.g., "User#save" or "User" or "")
          def scope_id
            class_path = current_class_name || ""
            method_name = current_method_name
            if method_name
              "#{class_path}##{method_name}"
            else
              class_path
            end
          end

          # Get variables that were defined/modified in this context (not from parent)
          def local_variables
            @variables.keys
          end
        end

        def initialize
          @literal_type_cache = {}
        end

        # Convert Prism AST to IR graph
        # @param prism_node [Prism::Node] Prism AST node
        # @param context [Context] Conversion context
        # @return [IR::Node, nil] IR node
        def convert(prism_node, context = Context.new)
          case prism_node
          when Prism::IntegerNode, Prism::FloatNode, Prism::StringNode,
               Prism::SymbolNode, Prism::TrueNode, Prism::FalseNode,
               Prism::NilNode, Prism::InterpolatedStringNode, Prism::RangeNode,
               Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode,
               Prism::ImaginaryNode, Prism::RationalNode,
               Prism::XStringNode, Prism::InterpolatedXStringNode
            convert_literal(prism_node)

          when Prism::ArrayNode
            convert_array_literal(prism_node, context)

          when Prism::HashNode
            convert_hash_literal(prism_node, context)

          when Prism::LocalVariableWriteNode
            convert_local_variable_write(prism_node, context)

          when Prism::LocalVariableReadNode
            convert_local_variable_read(prism_node, context)

          when Prism::InstanceVariableWriteNode
            convert_instance_variable_write(prism_node, context)

          when Prism::InstanceVariableReadNode
            convert_instance_variable_read(prism_node, context)

          when Prism::ClassVariableWriteNode
            convert_class_variable_write(prism_node, context)

          when Prism::ClassVariableReadNode
            convert_class_variable_read(prism_node, context)

          # Compound assignments (||=, &&=, +=, etc.)
          when Prism::LocalVariableOrWriteNode
            convert_local_variable_or_write(prism_node, context)

          when Prism::LocalVariableAndWriteNode
            convert_local_variable_and_write(prism_node, context)

          when Prism::LocalVariableOperatorWriteNode
            convert_local_variable_operator_write(prism_node, context)

          when Prism::InstanceVariableOrWriteNode
            convert_instance_variable_or_write(prism_node, context)

          when Prism::InstanceVariableAndWriteNode
            convert_instance_variable_and_write(prism_node, context)

          when Prism::InstanceVariableOperatorWriteNode
            convert_instance_variable_operator_write(prism_node, context)

          when Prism::CallNode
            convert_call(prism_node, context)

          when Prism::IfNode
            convert_if(prism_node, context)

          when Prism::UnlessNode
            convert_unless(prism_node, context)

          when Prism::CaseNode
            convert_case(prism_node, context)

          when Prism::CaseMatchNode
            convert_case_match(prism_node, context)

          when Prism::StatementsNode
            convert_statements(prism_node, context)

          when Prism::DefNode
            convert_def(prism_node, context)

          when Prism::ConstantReadNode, Prism::ConstantPathNode
            convert_constant_read(prism_node, context)

          when Prism::ConstantWriteNode
            convert_constant_write(prism_node, context)

          when Prism::ClassNode, Prism::ModuleNode
            convert_class_or_module(prism_node, context)

          when Prism::SingletonClassNode
            convert_singleton_class(prism_node, context)

          when Prism::ReturnNode
            # Return statement - wrap in ReturnNode to track explicit returns
            value_node = if prism_node.arguments&.arguments&.first
                           convert(prism_node.arguments.arguments.first, context)
                         else
                           # return with no value returns nil
                           IR::LiteralNode.new(
                             type: Types::ClassInstance.new("NilClass"),
                             literal_value: nil,
                             values: nil,
                             loc: convert_loc(prism_node.location)
                           )
                         end
            IR::ReturnNode.new(
              value: value_node,
              loc: convert_loc(prism_node.location)
            )

          when Prism::SelfNode
            # self keyword - returns the current class instance
            IR::SelfNode.new(
              class_name: context.current_class_name || "Object",
              loc: convert_loc(prism_node.location)
            )

          when Prism::BeginNode
            convert_begin(prism_node, context)

          when Prism::RescueNode
            # Rescue clause - convert body statements
            convert_statements_body(prism_node.statements&.body, context)
          end
        end

        private

        def convert_literal(prism_node)
          type = infer_literal_type(prism_node)
          literal_value = extract_literal_value(prism_node)
          IR::LiteralNode.new(
            type: type,
            literal_value: literal_value,
            values: nil,
            loc: convert_loc(prism_node.location)
          )
        end

        # Extract the actual value from a literal node (for Symbol, Integer, String)
        def extract_literal_value(prism_node)
          case prism_node
          when Prism::SymbolNode
            prism_node.value.to_sym
          when Prism::IntegerNode
            prism_node.value
          when Prism::StringNode
            prism_node.content
          end
        end

        def convert_array_literal(prism_node, context)
          type = infer_array_element_type(prism_node)

          # Convert each element to an IR node
          value_nodes = prism_node.elements.filter_map do |elem|
            next if elem.nil?

            case elem
            when Prism::SplatNode
              # *arr → convert to CallNode for to_a
              splat_expr = convert(elem.expression, context)
              IR::CallNode.new(
                method: :to_a,
                receiver: splat_expr,
                args: [],
                block_params: [],
                block_body: nil,
                has_block: false,
                loc: convert_loc(elem.location)
              )
            else
              convert(elem, context)
            end
          end

          IR::LiteralNode.new(
            type: type,
            literal_value: nil,
            values: value_nodes.empty? ? nil : value_nodes,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_hash_literal(prism_node, context)
          type = infer_hash_element_types(prism_node)

          # Convert each value expression to an IR node
          value_nodes = []
          prism_node.elements.each do |elem|
            case elem
            when Prism::AssocNode
              # Convert value (key is just for type info, not tracked as dependency)
              value_node = convert(elem.value, context)
              value_nodes << value_node if value_node
            when Prism::AssocSplatNode
              # Handle **hash spread
              splat_node = convert(elem.value, context)
              value_nodes << splat_node if splat_node
            end
          end

          IR::LiteralNode.new(
            type: type,
            literal_value: nil,
            values: value_nodes.empty? ? nil : value_nodes,
            loc: convert_loc(prism_node.location)
          )
        end

        def infer_literal_type(prism_node)
          case prism_node
          when Prism::IntegerNode
            Types::ClassInstance.new("Integer")
          when Prism::FloatNode
            Types::ClassInstance.new("Float")
          when Prism::StringNode, Prism::InterpolatedStringNode
            Types::ClassInstance.new("String")
          when Prism::SymbolNode
            Types::ClassInstance.new("Symbol")
          when Prism::TrueNode
            Types::ClassInstance.new("TrueClass")
          when Prism::FalseNode
            Types::ClassInstance.new("FalseClass")
          when Prism::NilNode
            Types::ClassInstance.new("NilClass")
          when Prism::ArrayNode
            # Infer element type from array contents
            infer_array_element_type(prism_node)
          when Prism::HashNode
            infer_hash_element_types(prism_node)
          when Prism::RangeNode
            infer_range_element_type(prism_node)
          when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
            Types::ClassInstance.new("Regexp")
          when Prism::ImaginaryNode
            Types::ClassInstance.new("Complex")
          when Prism::RationalNode
            Types::ClassInstance.new("Rational")
          when Prism::XStringNode, Prism::InterpolatedXStringNode
            Types::ClassInstance.new("String")
          else
            Types::Unknown.instance
          end
        end

        def infer_range_element_type(range_node)
          left_type = range_node.left ? infer_literal_type(range_node.left) : nil
          right_type = range_node.right ? infer_literal_type(range_node.right) : nil

          types = [left_type, right_type].compact

          # No bounds at all (shouldn't happen in valid Ruby, but handle gracefully)
          return Types::RangeType.new if types.empty?

          unique_types = types.uniq

          element_type = if unique_types.size == 1
                           unique_types.first
                         else
                           Types::Union.new(unique_types)
                         end

          Types::RangeType.new(element_type)
        end

        def convert_local_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          write_node = IR::LocalWriteNode.new(
            name: prism_node.name,
            value: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, write_node)
          write_node
        end

        def convert_local_variable_read(prism_node, context)
          # Look up the most recent assignment
          write_node = context.lookup_variable(prism_node.name)
          # Share called_methods array with the write node/parameter for method-based inference
          called_methods = if write_node.is_a?(IR::LocalWriteNode) || write_node.is_a?(IR::ParamNode)
                             write_node.called_methods
                           else
                             []
                           end

          IR::LocalReadNode.new(
            name: prism_node.name,
            write_node: write_node,
            called_methods: called_methods,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_instance_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          class_name = context.current_class_name
          write_node = IR::InstanceVariableWriteNode.new(
            name: prism_node.name,
            class_name: class_name,
            value: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          # Register at class level so it's visible across methods
          context.register_instance_variable(prism_node.name, write_node)
          write_node
        end

        def convert_instance_variable_read(prism_node, context)
          # Look up from class level first
          write_node = context.lookup_instance_variable(prism_node.name)
          class_name = context.current_class_name
          called_methods = if write_node.is_a?(IR::InstanceVariableWriteNode) || write_node.is_a?(IR::ParamNode)
                             write_node.called_methods
                           else
                             []
                           end

          IR::InstanceVariableReadNode.new(
            name: prism_node.name,
            class_name: class_name,
            write_node: write_node,
            called_methods: called_methods,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_class_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          class_name = context.current_class_name
          write_node = IR::ClassVariableWriteNode.new(
            name: prism_node.name,
            class_name: class_name,
            value: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, write_node)
          write_node
        end

        def convert_class_variable_read(prism_node, context)
          write_node = context.lookup_variable(prism_node.name)
          class_name = context.current_class_name
          called_methods = if write_node.is_a?(IR::ClassVariableWriteNode) || write_node.is_a?(IR::ParamNode)
                             write_node.called_methods
                           else
                             []
                           end

          IR::ClassVariableReadNode.new(
            name: prism_node.name,
            class_name: class_name,
            write_node: write_node,
            called_methods: called_methods,
            loc: convert_loc(prism_node.location)
          )
        end

        # Compound assignment: x ||= value
        # Result type is union of original and new value type
        def convert_local_variable_or_write(prism_node, context)
          convert_or_write(prism_node, context, :local)
        end

        # Compound assignment: x &&= value
        # Result type is union of original and new value type
        def convert_local_variable_and_write(prism_node, context)
          convert_and_write(prism_node, context, :local)
        end

        # Compound assignment: x += value, x -= value, etc.
        # Result type depends on the operator method return type
        def convert_local_variable_operator_write(prism_node, context)
          convert_operator_write(prism_node, context, :local)
        end

        def convert_instance_variable_or_write(prism_node, context)
          convert_or_write(prism_node, context, :instance)
        end

        def convert_instance_variable_and_write(prism_node, context)
          convert_and_write(prism_node, context, :instance)
        end

        def convert_instance_variable_operator_write(prism_node, context)
          convert_operator_write(prism_node, context, :instance)
        end

        # Generic ||= handler
        # x ||= value means: if x is nil/false, x = value, else keep x
        # Type is union of original type and value type
        def convert_or_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          # Create merge node for union type (original | value)
          branches = []
          branches << original_node if original_node
          branches << value_node

          merge_node = if branches.size == 1
                         branches.first
                       else
                         IR::MergeNode.new(
                           branches: branches,
                           loc: convert_loc(prism_node.location)
                         )
                       end

          # Create write node with merged value
          write_node = create_write_node(prism_node.name, kind, merge_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Generic &&= handler
        # x &&= value means: if x is truthy, x = value, else keep x
        # Type is union of original type and value type
        def convert_and_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          # Create merge node for union type (original | value)
          branches = []
          branches << original_node if original_node
          branches << value_node

          merge_node = if branches.size == 1
                         branches.first
                       else
                         IR::MergeNode.new(
                           branches: branches,
                           loc: convert_loc(prism_node.location)
                         )
                       end

          write_node = create_write_node(prism_node.name, kind, merge_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Generic operator write handler (+=, -=, *=, etc.)
        # x += value is equivalent to x = x.+(value)
        # Type is the return type of the operator method
        def convert_operator_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          # Create a call node representing x.operator(value)
          call_node = IR::CallNode.new(
            method: prism_node.binary_operator,
            receiver: original_node,
            args: [value_node],
            block_params: [],
            block_body: nil,
            has_block: false,
            loc: convert_loc(prism_node.location)
          )

          # Create write node with call result as value
          write_node = create_write_node(prism_node.name, kind, call_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Helper to create the appropriate write node type based on kind
        def create_write_node(name, kind, value, context, location)
          loc = convert_loc(location)
          case kind
          when :local
            IR::LocalWriteNode.new(
              name: name,
              value: value,
              called_methods: [],
              loc: loc
            )
          when :instance
            IR::InstanceVariableWriteNode.new(
              name: name,
              class_name: context.current_class_name,
              value: value,
              called_methods: [],
              loc: loc
            )
          when :class
            IR::ClassVariableWriteNode.new(
              name: name,
              class_name: context.current_class_name,
              value: value,
              called_methods: [],
              loc: loc
            )
          end
        end

        # Helper to lookup variable by kind
        def lookup_by_kind(name, kind, context)
          case kind
          when :instance
            context.lookup_instance_variable(name)
          else
            context.lookup_variable(name)
          end
        end

        # Helper to register variable by kind
        def register_by_kind(name, node, kind, context)
          case kind
          when :instance
            context.register_instance_variable(name, node)
          else
            context.register_variable(name, node)
          end
        end

        def convert_call(prism_node, context)
          # Convert receiver - if nil and inside a class, create implicit SelfNode
          receiver_node = if prism_node.receiver
                            convert(prism_node.receiver, context)
                          elsif context.current_class_name
                            IR::SelfNode.new(
                              class_name: context.current_class_name,
                              loc: convert_loc(prism_node.location)
                            )
                          end

          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []

          has_block = !prism_node.block.nil?

          # Track method call on receiver for method-based type inference
          receiver_node.called_methods << prism_node.name if variable_node?(receiver_node) && !receiver_node.called_methods.include?(prism_node.name)

          # Handle container mutating methods (Hash#[]=, Array#[]=, Array#<<)
          receiver_node = handle_container_mutation(prism_node, receiver_node, args, context) if container_mutating_method?(prism_node.name, receiver_node)

          call_node = IR::CallNode.new(
            method: prism_node.name,
            receiver: receiver_node,
            args: args,
            block_params: [],
            block_body: nil,
            has_block: has_block,
            loc: convert_loc(prism_node.location)
          )

          # Handle block if present (but not block arguments like &block)
          if prism_node.block.is_a?(Prism::BlockNode)
            block_body = convert_block(prism_node.block, call_node, context)
            # Recreate CallNode with block_body since Data.define is immutable
            call_node = IR::CallNode.new(
              method: prism_node.name,
              receiver: receiver_node,
              args: args,
              block_params: call_node.block_params,
              block_body: block_body,
              has_block: true,
              loc: convert_loc(prism_node.location)
            )
          end

          call_node
        end

        # Check if node is any variable node (for method call tracking)
        def variable_node?(node)
          node.is_a?(IR::LocalWriteNode) ||
            node.is_a?(IR::LocalReadNode) ||
            node.is_a?(IR::InstanceVariableWriteNode) ||
            node.is_a?(IR::InstanceVariableReadNode) ||
            node.is_a?(IR::ClassVariableWriteNode) ||
            node.is_a?(IR::ClassVariableReadNode) ||
            node.is_a?(IR::ParamNode)
        end

        # Check if node is a local variable node (for indexed assignment)
        def local_variable_node?(node)
          node.is_a?(IR::LocalWriteNode) || node.is_a?(IR::LocalReadNode)
        end

        def extract_literal_type(ir_node)
          case ir_node
          when IR::LiteralNode
            ir_node.type
          else
            Types::Unknown.instance
          end
        end

        def widen_to_hash_type(original_type, key_arg, value_type)
          # When mixing key types, widen to generic HashType
          new_key_type = infer_key_type(key_arg)

          case original_type
          when Types::HashShape
            # HashShape with symbol keys + non-symbol key -> widen to Hash[Symbol | NewKeyType, ValueUnion]
            original_key_type = Types::ClassInstance.new("Symbol")
            original_value_types = original_type.fields.values.uniq
            all_value_types = (original_value_types + [value_type]).uniq

            combined_key_type = Types::Union.new([original_key_type, new_key_type].uniq)
            combined_value_type = all_value_types.size == 1 ? all_value_types.first : Types::Union.new(all_value_types)

            Types::HashType.new(combined_key_type, combined_value_type)
          when Types::HashType
            # Already a HashType, just union the key and value types
            combined_key_type = union_types(original_type.key_type, new_key_type)
            combined_value_type = union_types(original_type.value_type, value_type)
            Types::HashType.new(combined_key_type, combined_value_type)
          else
            Types::HashType.new(new_key_type, value_type)
          end
        end

        def union_types(type1, type2)
          return type2 if type1.nil? || type1.is_a?(Types::Unknown)
          return type1 if type2.nil? || type2.is_a?(Types::Unknown)
          return type1 if type1 == type2

          types = []
          types += type1.is_a?(Types::Union) ? type1.types : [type1]
          types += type2.is_a?(Types::Union) ? type2.types : [type2]
          Types::Union.new(types.uniq)
        end

        def infer_key_type(key_arg)
          case key_arg
          when Prism::SymbolNode
            Types::ClassInstance.new("Symbol")
          when Prism::StringNode
            Types::ClassInstance.new("String")
          when Prism::IntegerNode
            Types::ClassInstance.new("Integer")
          else
            Types::Unknown.instance
          end
        end

        # Check if method is a container mutating method
        def container_mutating_method?(method, receiver_node)
          return false unless local_variable_node?(receiver_node)

          receiver_type = get_receiver_type(receiver_node)
          return false unless receiver_type

          case method
          when :[]= then hash_like?(receiver_type) || array_like?(receiver_type)
          when :<<  then array_like?(receiver_type)
          else false
          end
        end

        # Get receiver's current type
        def get_receiver_type(receiver_node)
          return nil unless receiver_node.respond_to?(:write_node)

          write_node = receiver_node.write_node
          return nil unless write_node
          return nil unless write_node.respond_to?(:value)

          value = write_node.value
          return nil unless value.respond_to?(:type)

          value.type
        end

        # Check if type is hash-like
        def hash_like?(type)
          type.is_a?(Types::HashShape) || type.is_a?(Types::HashType)
        end

        # Check if type is array-like
        def array_like?(type)
          type.is_a?(Types::ArrayType)
        end

        # Handle container mutation by creating new LocalWriteNode with merged type
        def handle_container_mutation(prism_node, receiver_node, args, context)
          merged_type = compute_merged_type(receiver_node, prism_node.name, args, prism_node)
          return receiver_node unless merged_type

          # Create new LocalWriteNode with merged type
          new_write = IR::LocalWriteNode.new(
            name: receiver_node.name,
            value: IR::LiteralNode.new(type: merged_type, literal_value: nil, values: nil, loc: receiver_node.loc),
            called_methods: receiver_node.called_methods,
            loc: convert_loc(prism_node.location)
          )

          # Register for next line references
          context.register_variable(receiver_node.name, new_write)

          # Return new LocalReadNode pointing to new write_node
          IR::LocalReadNode.new(
            name: receiver_node.name,
            write_node: new_write,
            called_methods: receiver_node.called_methods,
            loc: receiver_node.loc
          )
        end

        # Compute merged type for container mutation
        def compute_merged_type(receiver_node, method, args, prism_node)
          original_type = get_receiver_type(receiver_node)
          return nil unless original_type

          case method
          when :[]=
            if hash_like?(original_type)
              compute_hash_assignment_type(original_type, args, prism_node)
            elsif array_like?(original_type)
              compute_array_assignment_type(original_type, args)
            end
          when :<<
            compute_array_append_type(original_type, args) if array_like?(original_type)
          end
        end

        # Compute Hash type after indexed assignment
        def compute_hash_assignment_type(original_type, args, prism_node)
          return nil unless args.size == 2

          key_arg = prism_node.arguments.arguments[0]
          value_type = extract_literal_type(args[1])

          case original_type
          when Types::HashShape
            if key_arg.is_a?(Prism::SymbolNode)
              # Symbol key → keep HashShape, add field
              key_name = key_arg.value.to_sym
              Types::HashShape.new(original_type.fields.merge(key_name => value_type))
            else
              # Non-symbol key → widen to HashType
              widen_to_hash_type(original_type, key_arg, value_type)
            end
          when Types::HashType
            # Empty hash (Unknown types) + symbol key → becomes HashShape with one field
            if empty_hash_type?(original_type) && key_arg.is_a?(Prism::SymbolNode)
              key_name = key_arg.value.to_sym
              Types::HashShape.new({ key_name => value_type })
            else
              key_type = infer_key_type(key_arg)
              Types::HashType.new(
                union_types(original_type.key_type, key_type),
                union_types(original_type.value_type, value_type)
              )
            end
          end
        end

        # Check if HashType is empty (has Unknown types)
        def empty_hash_type?(hash_type)
          (hash_type.key_type.nil? || hash_type.key_type.is_a?(Types::Unknown)) &&
            (hash_type.value_type.nil? || hash_type.value_type.is_a?(Types::Unknown))
        end

        # Compute Array type after indexed assignment
        def compute_array_assignment_type(original_type, args)
          return nil unless args.size == 2

          value_type = extract_literal_type(args[1])
          combined = union_types(original_type.element_type, value_type)
          Types::ArrayType.new(combined)
        end

        # Compute Array type after << operator
        def compute_array_append_type(original_type, args)
          return nil unless args.size == 1

          value_type = extract_literal_type(args[0])
          combined = union_types(original_type.element_type, value_type)
          Types::ArrayType.new(combined)
        end

        # Extract IR param nodes from a Prism parameter node
        # Handles destructuring (MultiTargetNode) by flattening nested params
        def extract_param_nodes(param, kind, context, default_value: nil)
          case param
          when Prism::MultiTargetNode
            # Destructuring parameter like (a, b) - extract all nested params
            param.lefts.flat_map { |p| extract_param_nodes(p, kind, context) } +
              param.rights.flat_map { |p| extract_param_nodes(p, kind, context) }
          when Prism::RequiredParameterNode, Prism::OptionalParameterNode
            param_node = IR::ParamNode.new(
              name: param.name,
              kind: kind,
              default_value: default_value,
              called_methods: [],
              loc: convert_loc(param.location)
            )
            context.register_variable(param.name, param_node)
            [param_node]
          else
            []
          end
        end

        def convert_block(block_node, call_node, context)
          # Create block parameter slots and register them in context
          block_context = context.fork(:block)

          if block_node.parameters.is_a?(Prism::BlockParametersNode)
            parameters_node = block_node.parameters.parameters
            if parameters_node
              # Collect all parameters in order
              params = []
              params.concat(parameters_node.requireds) if parameters_node.requireds
              params.concat(parameters_node.optionals) if parameters_node.optionals

              params.each_with_index do |param, index|
                param_name, param_loc = case param
                                        when Prism::RequiredParameterNode
                                          [param.name, param.location]
                                        when Prism::OptionalParameterNode
                                          [param.name, param.location]
                                        when Prism::MultiTargetNode
                                          # Destructuring parameters like |a, (b, c)|
                                          # For now, skip complex cases
                                          next
                                        else
                                          next
                                        end

                slot = IR::BlockParamSlot.new(
                  index: index,
                  call_node: call_node,
                  loc: convert_loc(param_loc)
                )
                call_node.block_params << slot
                block_context.register_variable(param_name, slot)
              end
            end
          end

          # Convert block body and return it for block return type inference
          block_node.body ? convert(block_node.body, block_context) : nil
        end

        def convert_if(prism_node, context)
          # Convert then branch
          then_context = context.fork(:then)
          then_node = convert(prism_node.statements, then_context) if prism_node.statements

          # Convert else branch (could be IfNode, ElseNode, or nil)
          else_context = context.fork(:else)
          else_node = if prism_node.subsequent
                        case prism_node.subsequent
                        when Prism::IfNode
                          convert_if(prism_node.subsequent, else_context)
                        when Prism::ElseNode
                          convert(prism_node.subsequent.statements, else_context)
                        end
                      end

          # Create merge nodes for variables modified in branches
          merge_modified_variables(context, then_context, else_context, then_node, else_node, prism_node.location)
        end

        def convert_unless(prism_node, context)
          # Unless is like if with inverted condition
          # We treat the unless body as the "else" branch and the consequent as "then"

          unless_context = context.fork(:unless)
          unless_node = convert(prism_node.statements, unless_context) if prism_node.statements

          else_context = context.fork(:else)
          else_node = (convert(prism_node.else_clause.statements, else_context) if prism_node.else_clause)

          merge_modified_variables(context, unless_context, else_context, unless_node, else_node, prism_node.location)
        end

        def convert_case(prism_node, context)
          branches = []
          branch_contexts = []

          # Convert each when clause
          prism_node.conditions&.each do |when_node|
            when_context = context.fork(:when)
            if when_node.statements
              when_result = convert(when_node.statements, when_context)
              branches << (when_result || create_nil_literal(prism_node.location))
            else
              # Empty when clause → nil
              branches << create_nil_literal(prism_node.location)
            end
            branch_contexts << when_context
          end

          # Convert else clause
          if prism_node.else_clause
            else_context = context.fork(:else)
            else_result = convert(prism_node.else_clause.statements, else_context)
            branches << (else_result || create_nil_literal(prism_node.location))
            branch_contexts << else_context
          else
            # If no else clause, nil is possible
            branches << create_nil_literal(prism_node.location)
          end

          # Merge modified variables across all branches
          merge_case_variables(context, branch_contexts, branches, prism_node.location)
        end

        def convert_case_match(prism_node, context)
          # Pattern matching case (Ruby 3.0+)
          # For now, treat it similarly to regular case
          convert_case(prism_node, context)
        end

        def convert_statements(prism_node, context)
          last_node = nil
          prism_node.body.each do |stmt|
            last_node = convert(stmt, context)
          end
          last_node
        end

        # Helper to convert an array of statement bodies
        # @param body [Array<Prism::Node>, nil] Array of statement nodes
        # @param context [Context] Conversion context
        # @return [Array<IR::Node>] Array of converted IR nodes
        def convert_statements_body(body, context)
          return [] unless body

          nodes = []
          body.each do |stmt|
            node = convert(stmt, context)
            nodes << node if node
          end
          nodes
        end

        # Convert begin/rescue/ensure block
        def convert_begin(prism_node, context)
          body_nodes = extract_begin_body_nodes(prism_node, context)
          # Return the last node (represents the value of the begin block)
          body_nodes.last
        end

        # Extract all body nodes from a BeginNode (for DefNode bodies with rescue/ensure)
        # @param begin_node [Prism::BeginNode] The begin node
        # @param context [Context] Conversion context
        # @return [Array<IR::Node>] Array of all body nodes
        def extract_begin_body_nodes(begin_node, context)
          body_nodes = []

          # Convert main body statements
          body_nodes.concat(convert_statements_body(begin_node.statements.body, context)) if begin_node.statements

          # Convert rescue clause(s)
          rescue_clause = begin_node.rescue_clause
          while rescue_clause
            rescue_nodes = convert_statements_body(rescue_clause.statements&.body, context)
            body_nodes.concat(rescue_nodes)
            rescue_clause = rescue_clause.subsequent
          end

          # Convert else clause
          if begin_node.else_clause
            else_nodes = convert_statements_body(begin_node.else_clause.statements&.body, context)
            body_nodes.concat(else_nodes)
          end

          # Convert ensure clause
          if begin_node.ensure_clause
            ensure_nodes = convert_statements_body(begin_node.ensure_clause.statements&.body, context)
            body_nodes.concat(ensure_nodes)
          end

          body_nodes
        end

        def convert_def(prism_node, context)
          def_context = context.fork(:method)
          def_context.current_method = prism_node.name.to_s

          # Convert parameters
          params = []
          if prism_node.parameters
            parameters_node = prism_node.parameters

            # Required parameters
            parameters_node.requireds&.each do |param|
              extract_param_nodes(param, :required, def_context).each do |param_node|
                params << param_node
              end
            end

            # Optional parameters
            parameters_node.optionals&.each do |param|
              default_node = convert(param.value, def_context)
              param_node = IR::ParamNode.new(
                name: param.name,
                kind: :optional,
                default_value: default_node,
                called_methods: [],
                loc: convert_loc(param.location)
              )
              params << param_node
              def_context.register_variable(param.name, param_node)
            end

            # Rest parameter (*args)
            if parameters_node.rest.is_a?(Prism::RestParameterNode)
              rest = parameters_node.rest
              param_node = IR::ParamNode.new(
                name: rest.name || :*,
                kind: :rest,
                default_value: nil,
                called_methods: [],
                loc: convert_loc(rest.location)
              )
              params << param_node
              def_context.register_variable(rest.name, param_node) if rest.name
            end

            # Required keyword parameters (name:)
            parameters_node.keywords&.each do |kw|
              case kw
              when Prism::RequiredKeywordParameterNode
                param_node = IR::ParamNode.new(
                  name: kw.name,
                  kind: :keyword_required,
                  default_value: nil,
                  called_methods: [],
                  loc: convert_loc(kw.location)
                )
                params << param_node
                def_context.register_variable(kw.name, param_node)
              when Prism::OptionalKeywordParameterNode
                default_node = convert(kw.value, def_context)
                param_node = IR::ParamNode.new(
                  name: kw.name,
                  kind: :keyword_optional,
                  default_value: default_node,
                  called_methods: [],
                  loc: convert_loc(kw.location)
                )
                params << param_node
                def_context.register_variable(kw.name, param_node)
              end
            end

            # Keyword rest parameter (**kwargs)
            if parameters_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
              kwrest = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(
                name: kwrest.name || :**,
                kind: :keyword_rest,
                default_value: nil,
                called_methods: [],
                loc: convert_loc(kwrest.location)
              )
              params << param_node
              def_context.register_variable(kwrest.name, param_node) if kwrest.name
            elsif parameters_node.keyword_rest.is_a?(Prism::ForwardingParameterNode)
              # Forwarding parameter (...)
              fwd = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(
                name: :"...",
                kind: :forwarding,
                default_value: nil,
                called_methods: [],
                loc: convert_loc(fwd.location)
              )
              params << param_node
            end

            # Block parameter (&block)
            if parameters_node.block
              block = parameters_node.block
              param_node = IR::ParamNode.new(
                name: block.name || :&,
                kind: :block,
                default_value: nil,
                called_methods: [],
                loc: convert_loc(block.location)
              )
              params << param_node
              def_context.register_variable(block.name, param_node) if block.name
            end
          end

          # Convert method body - collect all body nodes
          body_nodes = []

          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, def_context)
              body_nodes << node if node
            end
          elsif prism_node.body.is_a?(Prism::BeginNode)
            # Method with rescue/ensure block
            begin_node = prism_node.body
            body_nodes = extract_begin_body_nodes(begin_node, def_context)
          elsif prism_node.body
            node = convert(prism_node.body, def_context)
            body_nodes << node if node
          end

          # Collect all return points: explicit returns + implicit last expression
          return_node = compute_return_node(body_nodes, prism_node.name_loc)

          IR::DefNode.new(
            name: prism_node.name,
            params: params,
            return_node: return_node,
            body_nodes: body_nodes,
            loc: convert_loc(prism_node.name_loc)
          )
        end

        # Compute the return node for a method by collecting all return points
        # @param body_nodes [Array<IR::Node>] All nodes in the method body
        # @param loc [Prism::Location] Location for the MergeNode if needed
        # @return [IR::Node, nil] The return node (MergeNode if multiple returns)
        def compute_return_node(body_nodes, loc)
          return nil if body_nodes.empty?

          # Collect all explicit returns from the body
          explicit_returns = collect_returns(body_nodes)

          # The implicit return is the last non-ReturnNode in body
          implicit_return = body_nodes.reject { |n| n.is_a?(IR::ReturnNode) }.last

          # Determine all return points
          return_points = explicit_returns.dup
          return_points << implicit_return if implicit_return && !last_node_returns?(body_nodes)

          case return_points.size
          when 0
            nil
          when 1
            return_points.first
          else
            IR::MergeNode.new(
              branches: return_points,
              loc: convert_loc(loc)
            )
          end
        end

        # Collect all ReturnNode instances from body nodes (recursive)
        # Searches inside MergeNode branches to find nested returns from if/case
        # @param nodes [Array<IR::Node>] Nodes to search
        # @return [Array<IR::ReturnNode>] All explicit return nodes
        def collect_returns(nodes)
          returns = []
          nodes.each do |node|
            case node
            when IR::ReturnNode
              returns << node
            when IR::MergeNode
              returns.concat(collect_returns(node.branches))
            end
          end
          returns
        end

        # Check if the last node in body is a ReturnNode
        # @param body_nodes [Array<IR::Node>] Body nodes
        # @return [Boolean]
        def last_node_returns?(body_nodes)
          body_nodes.last.is_a?(IR::ReturnNode)
        end

        def convert_constant_read(prism_node, context)
          name = case prism_node
                 when Prism::ConstantReadNode
                   prism_node.name.to_s
                 when Prism::ConstantPathNode
                   prism_node.slice
                 else
                   prism_node.to_s
                 end

          IR::ConstantNode.new(
            name: name,
            dependency: context.lookup_constant(name),
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_constant_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          context.register_constant(prism_node.name.to_s, value_node)
          IR::ConstantNode.new(
            name: prism_node.name.to_s,
            dependency: value_node,
            loc: convert_loc(prism_node.location)
          )
        end

        def merge_modified_variables(parent_context, then_context, else_context, then_node, else_node, location)
          # Track which variables were modified in each branch
          then_vars = then_context&.local_variables || []
          else_vars = else_context&.local_variables || []

          # All variables modified in either branch
          modified_vars = (then_vars + else_vars).uniq

          # Create MergeNode for each modified variable
          modified_vars.each do |var_name|
            then_val = then_context&.variables&.[](var_name)
            else_val = else_context&.variables&.[](var_name)

            # Get the original value from parent context (before if statement)
            original_val = parent_context.lookup_variable(var_name)

            # Determine branches for merge
            branches = []
            if then_val
              branches << then_val
            elsif original_val
              # Variable not modified in then branch, use original
              branches << original_val
            end

            if else_val
              branches << else_val
            elsif original_val
              # Variable not modified in else branch, use original
              branches << original_val
            elsif then_val
              # Inline if/unless: no else branch and no original value
              # Add nil to represent "variable may not be assigned"
              nil_node = IR::LiteralNode.new(
                type: Types::ClassInstance.new("NilClass"),
                literal_value: nil,
                values: nil,
                loc: convert_loc(location)
              )
              branches << nil_node
            end

            # Create MergeNode only if we have multiple branches
            if branches.size > 1
              merge_node = IR::MergeNode.new(
                branches: branches.uniq,
                loc: convert_loc(location)
              )
              parent_context.register_variable(var_name, merge_node)
            elsif branches.size == 1
              # Only one branch has a value, use it directly
              parent_context.register_variable(var_name, branches.first)
            end
          end

          # Return MergeNode for the if expression value
          if then_node && else_node
            IR::MergeNode.new(
              branches: [then_node, else_node].compact,
              loc: convert_loc(location)
            )
          elsif then_node || else_node
            # Modifier form: one branch only → value or nil
            branch_node = then_node || else_node
            nil_node = IR::LiteralNode.new(
              type: Types::ClassInstance.new("NilClass"),
              literal_value: nil,
              values: nil,
              loc: convert_loc(location)
            )
            IR::MergeNode.new(
              branches: [branch_node, nil_node],
              loc: convert_loc(location)
            )
          end
        end

        def merge_case_variables(parent_context, branch_contexts, branches, location)
          # Collect all variables modified in any branch
          all_modified_vars = branch_contexts.flat_map { |ctx| ctx&.local_variables || [] }.uniq

          # Create MergeNode for each modified variable
          all_modified_vars.each do |var_name|
            # Collect values from all branches
            branch_contexts.map { |ctx| ctx&.variables&.[](var_name) }

            # Get original value from parent context
            original_val = parent_context.lookup_variable(var_name)

            # Build branches array
            merge_branches = branch_contexts.map.with_index do |ctx, _idx|
              ctx&.variables&.[](var_name) || original_val
            end.compact.uniq

            # Create MergeNode if we have multiple different values
            if merge_branches.size > 1
              merge_node = IR::MergeNode.new(
                branches: merge_branches,
                loc: convert_loc(location)
              )
              parent_context.register_variable(var_name, merge_node)
            elsif merge_branches.size == 1
              parent_context.register_variable(var_name, merge_branches.first)
            end
          end

          # Return MergeNode for the case expression value
          if branches.size > 1
            IR::MergeNode.new(
              branches: branches.compact.uniq,
              loc: convert_loc(location)
            )
          elsif branches.size == 1
            branches.first
          end
        end

        def create_nil_literal(location)
          IR::LiteralNode.new(
            type: Types::ClassInstance.new("NilClass"),
            literal_value: nil,
            values: nil,
            loc: convert_loc(location)
          )
        end

        def convert_class_or_module(prism_node, context)
          # Get class/module name first
          name = case prism_node.constant_path
                 when Prism::ConstantReadNode
                   prism_node.constant_path.name.to_s
                 when Prism::ConstantPathNode
                   prism_node.constant_path.slice
                 else
                   "Anonymous"
                 end

          # Create a new context for class/module scope with the full class path
          class_context = context.fork(:class)
          parent_path = context.current_class_name
          full_name = parent_path ? "#{parent_path}::#{name}" : name
          class_context.current_class = full_name

          # Collect all method definitions and nested classes from the body
          methods = []
          nested_classes = []
          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, class_context)
              if node.is_a?(IR::DefNode)
                methods << node
              elsif node.is_a?(IR::ClassModuleNode)
                # Store nested class/module for separate indexing with proper scope
                nested_classes << node
              end
            end
          end
          # Store nested classes in methods array (RuntimeAdapter handles both types)
          methods.concat(nested_classes)

          IR::ClassModuleNode.new(
            name: name,
            methods: methods,
            loc: convert_loc(prism_node.constant_path&.location || prism_node.location)
          )
        end

        def convert_singleton_class(prism_node, context)
          # Create a new context for singleton class scope
          singleton_context = context.fork(:class)

          # Generate singleton class name in format: <Class:ParentName>
          parent_name = context.current_class_name || "Object"
          singleton_name = "<Class:#{parent_name}>"
          singleton_context.current_class = singleton_name

          # Collect all method definitions from the body
          methods = []
          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, singleton_context)
              methods << node if node.is_a?(IR::DefNode)
            end
          end

          IR::ClassModuleNode.new(
            name: singleton_name,
            methods: methods,
            loc: convert_loc(prism_node.location)
          )
        end

        def infer_array_element_type(array_node)
          return Types::ArrayType.new if array_node.elements.empty?

          element_types = array_node.elements.filter_map do |elem|
            infer_literal_type(elem) unless elem.nil?
          end

          return Types::ArrayType.new if element_types.empty?

          # Deduplicate types
          unique_types = element_types.uniq

          element_type = if unique_types.size == 1
                           unique_types.first
                         else
                           Types::Union.new(unique_types)
                         end

          Types::ArrayType.new(element_type)
        end

        def infer_hash_element_types(hash_node)
          return Types::HashType.new if hash_node.elements.empty?

          # Check if all keys are symbols for HashShape
          all_symbol_keys = hash_node.elements.all? do |elem|
            elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)
          end

          if all_symbol_keys
            # Build HashShape with field types
            fields = {}
            hash_node.elements.each do |elem|
              next unless elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)

              field_name = elem.key.value.to_sym
              field_type = infer_literal_type(elem.value)
              fields[field_name] = field_type
            end
            Types::HashShape.new(fields)
          else
            # Non-symbol keys or mixed keys - return HashType
            key_types = []
            value_types = []

            hash_node.elements.each do |elem|
              case elem
              when Prism::AssocNode
                key_types << infer_literal_type(elem.key) if elem.key
                value_types << infer_literal_type(elem.value) if elem.value
              end
            end

            return Types::HashType.new if key_types.empty? && value_types.empty?

            # Deduplicate types
            unique_key_types = key_types.uniq
            unique_value_types = value_types.uniq

            key_type = if unique_key_types.size == 1
                         unique_key_types.first
                       elsif unique_key_types.empty?
                         Types::Unknown.instance
                       else
                         Types::Union.new(unique_key_types)
                       end

            value_type = if unique_value_types.size == 1
                           unique_value_types.first
                         elsif unique_value_types.empty?
                           Types::Unknown.instance
                         else
                           Types::Union.new(unique_value_types)
                         end

            Types::HashType.new(key_type, value_type)
          end
        end

        def convert_loc(prism_location)
          IR::Loc.new(
            line: prism_location.start_line,
            col_range: (prism_location.start_column...prism_location.end_column)
          )
        end
      end
    end
  end
end
