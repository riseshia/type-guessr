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
               Prism::NilNode, Prism::ArrayNode, Prism::HashNode,
               Prism::InterpolatedStringNode, Prism::RangeNode,
               Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
            convert_literal(prism_node)

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
          IR::LiteralNode.new(
            type: type,
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
            Types::ClassInstance.new("Range")
          when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
            Types::ClassInstance.new("Regexp")
          else
            Types::Unknown.instance
          end
        end

        def convert_local_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: :local,
            dependency: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        def convert_local_variable_read(prism_node, context)
          # Look up the most recent assignment
          dependency = context.lookup_variable(prism_node.name)
          # Create a new node with the read location pointing to the assignment
          # Share called_methods array with the assignment/parameter for duck typing
          called_methods = if dependency.is_a?(IR::VariableNode) || dependency.is_a?(IR::ParamNode)
                             dependency.called_methods
                           else
                             []
                           end

          IR::VariableNode.new(
            name: prism_node.name,
            kind: :local,
            dependency: dependency,
            called_methods: called_methods,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_instance_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: :instance,
            dependency: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        def convert_instance_variable_read(prism_node, context)
          dependency = context.lookup_variable(prism_node.name)
          called_methods = if dependency.is_a?(IR::VariableNode) || dependency.is_a?(IR::ParamNode)
                             dependency.called_methods
                           else
                             []
                           end

          IR::VariableNode.new(
            name: prism_node.name,
            kind: :instance,
            dependency: dependency,
            called_methods: called_methods,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_class_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: :class,
            dependency: value_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        def convert_class_variable_read(prism_node, context)
          dependency = context.lookup_variable(prism_node.name)
          called_methods = if dependency.is_a?(IR::VariableNode) || dependency.is_a?(IR::ParamNode)
                             dependency.called_methods
                           else
                             []
                           end

          IR::VariableNode.new(
            name: prism_node.name,
            kind: :class,
            dependency: dependency,
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
          original_node = context.lookup_variable(prism_node.name)
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

          # Create variable node with merged dependency
          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: kind,
            dependency: merge_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        # Generic &&= handler
        # x &&= value means: if x is truthy, x = value, else keep x
        # Type is union of original type and value type
        def convert_and_write(prism_node, context, kind)
          original_node = context.lookup_variable(prism_node.name)
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

          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: kind,
            dependency: merge_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        # Generic operator write handler (+=, -=, *=, etc.)
        # x += value is equivalent to x = x.+(value)
        # Type is the return type of the operator method
        def convert_operator_write(prism_node, context, kind)
          original_node = context.lookup_variable(prism_node.name)
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

          # Create variable node with call result as dependency
          var_node = IR::VariableNode.new(
            name: prism_node.name,
            kind: kind,
            dependency: call_node,
            called_methods: [],
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, var_node)
          var_node
        end

        def convert_call(prism_node, context)
          receiver_node = (convert(prism_node.receiver, context) if prism_node.receiver)

          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []

          has_block = !prism_node.block.nil?

          # Track method call on receiver for duck typing
          receiver_node.called_methods << prism_node.name if receiver_node.is_a?(IR::VariableNode) || receiver_node.is_a?(IR::ParamNode)

          # Handle indexed assignment: a[:key] = value
          # Replace receiver with updated node so it gets indexed with correct type
          if prism_node.name == :[]= && receiver_node.is_a?(IR::VariableNode)
            updated_receiver = handle_indexed_assignment(prism_node, receiver_node, args, context)
            receiver_node = updated_receiver if updated_receiver
          end

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

        def handle_indexed_assignment(prism_node, receiver_node, args, context)
          # a[:key] = value -> update a's type to include the new field
          return nil unless args.size == 2

          value_node = args[1]
          key_arg = prism_node.arguments.arguments[0]

          # Get the original variable
          original_var = context.lookup_variable(receiver_node.name)
          return nil unless original_var

          value_type = extract_literal_type(value_node)

          # Determine how to update the type based on key type
          updated_type = if key_arg.is_a?(Prism::SymbolNode)
                           key_name = key_arg.value.to_sym
                           merge_hash_field(original_var, key_name, value_type)
                         else
                           # Non-symbol key: widen to HashType
                           widen_to_hash_type(original_var, key_arg, value_type)
                         end
          return nil unless updated_type

          # Create new variable node with updated dependency
          updated_var = IR::VariableNode.new(
            name: receiver_node.name,
            kind: receiver_node.kind,
            dependency: IR::LiteralNode.new(type: updated_type, loc: receiver_node.loc),
            called_methods: receiver_node.called_methods,
            loc: convert_loc(prism_node.location)
          )
          context.register_variable(receiver_node.name, updated_var)
          updated_var
        end

        def extract_literal_type(ir_node)
          case ir_node
          when IR::LiteralNode
            ir_node.type
          else
            Types::Unknown.instance
          end
        end

        def merge_hash_field(original_var, key_name, value_type)
          # Get original type
          original_type = case original_var
                          when IR::VariableNode
                            original_var.dependency.is_a?(IR::LiteralNode) ? original_var.dependency.type : nil
                          when IR::LiteralNode
                            original_var.type
                          end

          case original_type
          when Types::HashShape
            # Add new field to existing shape
            new_fields = original_type.fields.merge(key_name => value_type)
            Types::HashShape.new(new_fields)
          when Types::HashType
            # Empty hash (Unknown types) becomes HashShape with one field
            Types::HashShape.new({ key_name => value_type }) if empty_hash_type?(original_type)
            # Otherwise keep as HashType (mixed keys)
          end
        end

        def empty_hash_type?(hash_type)
          (hash_type.key_type.nil? || hash_type.key_type.is_a?(Types::Unknown)) &&
            (hash_type.value_type.nil? || hash_type.value_type.is_a?(Types::Unknown))
        end

        def widen_to_hash_type(original_var, key_arg, value_type)
          # When mixing key types, widen to generic HashType
          new_key_type = infer_key_type(key_arg)

          # Get original type to preserve existing key/value types
          original_type = case original_var
                          when IR::VariableNode
                            original_var.dependency.is_a?(IR::LiteralNode) ? original_var.dependency.type : nil
                          when IR::LiteralNode
                            original_var.type
                          end

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
          else_node = if prism_node.consequent
                        case prism_node.consequent
                        when Prism::IfNode
                          convert_if(prism_node.consequent, else_context)
                        when Prism::ElseNode
                          convert(prism_node.consequent.statements, else_context)
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
          else_node = if prism_node.consequent
                        case prism_node.consequent
                        when Prism::ElseNode
                          convert(prism_node.consequent.statements, else_context)
                        end
                      end

          merge_modified_variables(context, unless_context, else_context, unless_node, else_node, prism_node.location)
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

        # Collect all ReturnNode instances from body nodes (non-recursive)
        # @param nodes [Array<IR::Node>] Nodes to search
        # @return [Array<IR::ReturnNode>] All explicit return nodes
        def collect_returns(nodes)
          nodes.select { |n| n.is_a?(IR::ReturnNode) }
        end

        # Check if the last node in body is a ReturnNode
        # @param body_nodes [Array<IR::Node>] Body nodes
        # @return [Boolean]
        def last_node_returns?(body_nodes)
          body_nodes.last.is_a?(IR::ReturnNode)
        end

        def convert_constant_read(prism_node, _context)
          # For now, we don't have constant definition tracking
          # Return a constant node with no dependency
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
            dependency: nil,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_constant_write(prism_node, context)
          value_node = convert(prism_node.value, context)
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
          else
            then_node || else_node
          end
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

          # Create a new context for class/module scope with the class name set
          class_context = context.fork(:class)
          class_context.current_class = name

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
