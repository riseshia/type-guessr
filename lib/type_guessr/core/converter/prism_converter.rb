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
          def initialize(parent = nil)
            @parent = parent
            @variables = {} # name => node
            @scope_type = nil # :class, :method, :block, :top_level
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
            child
          end

          def scope_type
            @scope_type || @parent&.scope_type
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
               Prism::NilNode, Prism::ArrayNode, Prism::HashNode
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

          when Prism::ConstantReadNode
            convert_constant_read(prism_node, context)

          when Prism::ConstantWriteNode
            convert_constant_write(prism_node, context)
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
          when Prism::StringNode
            Types::ClassInstance.new("String")
          when Prism::SymbolNode
            Types::ClassInstance.new("Symbol")
          when Prism::TrueNode, Prism::FalseNode
            Types::ClassInstance.new("TrueClass") # or FalseClass, using TrueClass for simplicity
          when Prism::NilNode
            Types::ClassInstance.new("NilClass")
          when Prism::ArrayNode
            # For now, return Array without element type
            # TODO: infer element type from array contents
            Types::ArrayType.new
          when Prism::HashNode
            # For now, return Hash
            # TODO: infer HashShape from hash contents
            Types::ClassInstance.new("Hash")
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
          context.lookup_variable(prism_node.name)
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
          context.lookup_variable(prism_node.name)
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
          context.lookup_variable(prism_node.name)
        end

        def convert_call(prism_node, context)
          receiver_node = (convert(prism_node.receiver, context) if prism_node.receiver)

          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []

          call_node = IR::CallNode.new(
            method: prism_node.name,
            receiver: receiver_node,
            args: args,
            block_params: [],
            loc: convert_loc(prism_node.location)
          )

          # Track method call on receiver for duck typing
          receiver_node.called_methods << prism_node.name if receiver_node.is_a?(IR::VariableNode) || receiver_node.is_a?(IR::ParamNode)

          # Handle block if present
          convert_block(prism_node.block, call_node, context) if prism_node.block

          call_node
        end

        def convert_block(block_node, call_node, context)
          # Create block parameter slots and register them in context
          block_context = context.fork(:block)

          if block_node.parameters.is_a?(Prism::BlockParametersNode)
            parameters_node = block_node.parameters.parameters
            return unless parameters_node

            # Collect all parameters in order
            params = []
            params.concat(parameters_node.requireds) if parameters_node.requireds
            params.concat(parameters_node.optionals) if parameters_node.optionals

            params.each_with_index do |param, index|
              param_name = case param
                           when Prism::RequiredParameterNode
                             param.name
                           when Prism::OptionalParameterNode
                             param.name
                           when Prism::MultiTargetNode
                             # Destructuring parameters like |a, (b, c)|
                             # For now, skip complex cases
                             next
                           else
                             next
                           end

              slot = IR::BlockParamSlot.new(index: index, call_node: call_node)
              call_node.block_params << slot
              block_context.register_variable(param_name, slot)
            end
          end

          # Convert block body
          convert(block_node.body, block_context) if block_node.body
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

        def convert_def(prism_node, context)
          def_context = context.fork(:method)

          # Convert parameters
          params = []
          if prism_node.parameters
            parameters_node = prism_node.parameters

            # Required parameters
            parameters_node.requireds&.each do |param|
              param_node = IR::ParamNode.new(
                name: param.name,
                default_value: nil,
                called_methods: [],
                loc: convert_loc(param.location)
              )
              params << param_node
              def_context.register_variable(param.name, param_node)
            end

            # Optional parameters
            parameters_node.optionals&.each do |param|
              default_node = convert(param.value, def_context)
              param_node = IR::ParamNode.new(
                name: param.name,
                default_value: default_node,
                called_methods: [],
                loc: convert_loc(param.location)
              )
              params << param_node
              def_context.register_variable(param.name, param_node)
            end
          end

          # Convert method body
          return_node = (convert(prism_node.body, def_context) if prism_node.body)

          IR::DefNode.new(
            name: prism_node.name,
            params: params,
            return_node: return_node,
            loc: convert_loc(prism_node.location)
          )
        end

        def convert_constant_read(prism_node, _context)
          # For now, we don't have constant definition tracking
          # Return a constant node with no dependency
          IR::ConstantNode.new(
            name: prism_node.name.to_s,
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

        def merge_modified_variables(_parent_context, _then_context, _else_context, then_node, else_node, location)
          # For now, return the last node from then branch as the merge result
          # In a full implementation, we would:
          # 1. Track which variables were modified in each branch
          # 2. Create MergeNode for each modified variable
          # 3. Register merged variables in parent context

          # Simple implementation: if both branches exist, create a merge node
          if then_node && else_node
            IR::MergeNode.new(
              branches: [then_node, else_node].compact,
              loc: convert_loc(location)
            )
          else
            then_node || else_node
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
