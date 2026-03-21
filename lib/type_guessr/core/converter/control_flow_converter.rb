# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Control flow (if/case/begin/or/and), variable merging, and rescue methods for PrismConverter
      class PrismConverter
        # Register exception variable from rescue clause (=> e)
        # @param rescue_clause [Prism::RescueNode] The rescue clause
        # @param context [Context] Conversion context
        private def register_rescue_variable(rescue_clause, context)
          var_name = rescue_clause.reference.name
          exception_type = infer_rescue_exception_type(rescue_clause.exceptions)
          loc = convert_loc(rescue_clause.reference.location)

          value_node = IR::LiteralNode.new(exception_type, nil, nil, [], loc)

          write_node = IR::LocalWriteNode.new(var_name, value_node, [], loc)

          context.register_variable(var_name, write_node)
        end

        # Infer exception type from rescue clause's exception list
        # @param exceptions [Array<Prism::Node>] List of exception class nodes
        # @return [Types::ClassInstance, Types::Union] Inferred exception type
        private def infer_rescue_exception_type(exceptions)
          # Default to StandardError if no exception class specified (rescue => e)
          return Types::ClassInstance.new("StandardError") if exceptions.empty?

          types = exceptions.map do |exc|
            class_name = case exc
                         when Prism::ConstantReadNode
                           exc.name.to_s
                         when Prism::ConstantPathNode
                           # Handle namespaced constants like Net::HTTPError
                           begin
                             exc.full_name
                           rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
                             "StandardError"
                           end
                         else
                           "StandardError"
                         end
            Types::ClassInstance.new(class_name)
          end

          types.size == 1 ? types.first : Types::Union.new(types)
        end

        private def convert_if(prism_node, context)
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

        private def convert_unless(prism_node, context)
          # Unless is like if with inverted condition
          # We treat the unless body as the "else" branch and the consequent as "then"

          unless_context = context.fork(:unless)
          unless_node = convert(prism_node.statements, unless_context) if prism_node.statements

          else_context = context.fork(:else)
          else_node = (convert(prism_node.else_clause.statements, else_context) if prism_node.else_clause)

          result = merge_modified_variables(context, unless_context, else_context, unless_node, else_node, prism_node.location)

          # Guard clause narrowing: `return/raise unless x` → x is truthy after
          narrow_guard_variable(prism_node.predicate, :truthy, context, prism_node.location) if guard_clause?(unless_node)

          result
        end

        private def convert_case(prism_node, context)
          branches = []
          branch_contexts = []

          # Convert each when clause
          prism_node.conditions&.each do |when_node|
            when_context = context.fork(:when)
            if when_node.statements
              when_result = convert(when_node.statements, when_context)
              # Skip non-returning branches (raise, fail, etc.)
              unless non_returning?(when_result)
                branches << (when_result || create_nil_literal(prism_node.location))
                branch_contexts << when_context
              end
            else
              # Empty when clause → nil
              branches << create_nil_literal(prism_node.location)
              branch_contexts << when_context
            end
          end

          # Convert else clause
          if prism_node.else_clause
            else_context = context.fork(:else)
            else_result = convert(prism_node.else_clause.statements, else_context)
            # Skip non-returning else clause (raise, fail, etc.)
            unless non_returning?(else_result)
              branches << (else_result || create_nil_literal(prism_node.location))
              branch_contexts << else_context
            end
          else
            # If no else clause, nil is possible
            branches << create_nil_literal(prism_node.location)
          end

          # Merge modified variables across all branches
          merge_case_variables(context, branch_contexts, branches, prism_node.location)
        end

        private def convert_case_match(prism_node, context)
          # Pattern matching case (Ruby 3.0+)
          # For now, treat it similarly to regular case
          convert_case(prism_node, context)
        end

        private def convert_statements(prism_node, context)
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
        private def convert_statements_body(body, context)
          return [] unless body

          nodes = []
          body.each do |stmt|
            node = convert(stmt, context)
            nodes << node if node
          end
          nodes
        end

        # Convert begin/rescue/ensure block
        private def convert_begin(prism_node, context)
          body_nodes = extract_begin_body_nodes(prism_node, context)
          # Return the last node (represents the value of the begin block)
          body_nodes.last
        end

        # Convert || (or) operator to OrNode
        # a || b → LHS evaluated first, RHS only if LHS is falsy
        private def convert_or_node(prism_node, context)
          left_node = convert(prism_node.left, context)
          right_node = convert(prism_node.right, context)

          return nil if left_node.nil? && right_node.nil?
          return left_node if right_node.nil?
          return right_node if left_node.nil?

          IR::OrNode.new(left_node, right_node, [], convert_loc(prism_node.location))
        end

        # Convert && (and) operator to MergeNode
        # a && b → result is either a or b (short-circuit evaluation)
        private def convert_and_node(prism_node, context)
          left_node = convert(prism_node.left, context)
          right_node = convert(prism_node.right, context)

          branches = [left_node, right_node].compact
          return nil if branches.empty?
          return branches.first if branches.size == 1

          IR::MergeNode.new(branches, [], convert_loc(prism_node.location))
        end

        # Convert h[:key] ||= value → OrNode(h.[](:key), value)
        private def convert_index_or_write(prism_node, context)
          receiver_node = convert(prism_node.receiver, context)
          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []
          value_node = convert(prism_node.value, context)

          read_call = IR::CallNode.new(:[], receiver_node, args, [], nil, false, [], convert_loc(prism_node.opening_loc))

          IR::OrNode.new(read_call, value_node, [], convert_loc(prism_node.location))
        end

        # Convert multiple assignment (a, b, c = expr)
        # Creates synthetic value[index] calls for each target variable
        private def convert_multi_write(prism_node, context)
          value_node = convert(prism_node.value, context)

          # lefts: variables before splat → value[0], value[1], ...
          prism_node.lefts.each_with_index do |target, index|
            assign_multi_write_target(target, value_node, index, context)
          end

          # rest: splat variable → ArrayType(Unknown)
          if prism_node.rest.is_a?(Prism::SplatNode) && prism_node.rest.expression
            splat_target = prism_node.rest.expression
            splat_value = IR::LiteralNode.new(
              Types::ArrayType.new, nil, nil, [], convert_loc(splat_target.location)
            )
            register_multi_write_variable(splat_target, splat_value, context)
          end

          # rights: variables after splat → value[-n], value[-(n-1)], ...
          prism_node.rights.each_with_index do |target, index|
            negative_index = -(prism_node.rights.size - index)
            assign_multi_write_target(target, value_node, negative_index, context)
          end

          value_node
        end

        # Create synthetic value[index] call and register the target variable
        private def assign_multi_write_target(target, value_node, index, context)
          loc = convert_loc(target.location)
          index_literal = IR::LiteralNode.new(
            Types::ClassInstance.for("Integer"), index, nil, [], loc
          )
          call_node = IR::CallNode.new(:[], value_node, [index_literal], [], nil, false, [], loc)
          register_multi_write_variable(target, call_node, context)
        end

        # Register a multi-write target variable (local or instance variable)
        private def register_multi_write_variable(target, value_node, context)
          loc = convert_loc(target.location)
          case target
          when Prism::LocalVariableTargetNode
            write_node = IR::LocalWriteNode.new(target.name, value_node, [], loc)
            context.register_variable(target.name, write_node)
          when Prism::InstanceVariableTargetNode
            write_node = IR::InstanceVariableWriteNode.new(
              target.name, context.current_class_name, value_node, [], loc
            )
            context.register_instance_variable(target.name, write_node)
          end
        end

        # Extract all body nodes from a BeginNode (for DefNode bodies with rescue/ensure)
        # @param begin_node [Prism::BeginNode] The begin node
        # @param context [Context] Conversion context
        # @return [Array<IR::Node>] Array of all body nodes
        private def extract_begin_body_nodes(begin_node, context)
          body_nodes = []

          # Convert main body statements
          body_nodes.concat(convert_statements_body(begin_node.statements.body, context)) if begin_node.statements

          # Convert rescue clause(s)
          rescue_clause = begin_node.rescue_clause
          while rescue_clause
            # Register exception variable (=> e) if present
            register_rescue_variable(rescue_clause, context) if rescue_clause.reference.is_a?(Prism::LocalVariableTargetNode)

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

        private def merge_modified_variables(parent_context, then_context, else_context, then_node, else_node, location)
          # Skip non-returning branches (raise, fail, etc.)
          then_node = nil if non_returning?(then_node)
          else_node = nil if non_returning?(else_node)

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
                Types::ClassInstance.for("NilClass"), nil, nil, [], convert_loc(location)
              )
              branches << nil_node
            end

            # Create MergeNode only if we have multiple branches
            if branches.size > 1
              merge_node = IR::MergeNode.new(branches.uniq, [], convert_loc(location))
              parent_context.register_variable(var_name, merge_node)
            elsif branches.size == 1
              # Only one branch has a value, use it directly
              parent_context.register_variable(var_name, branches.first)
            end
          end

          # Return MergeNode for the if expression value
          if then_node && else_node
            IR::MergeNode.new([then_node, else_node].compact, [], convert_loc(location))
          elsif then_node || else_node
            # Modifier form: one branch only → value or nil
            branch_node = then_node || else_node
            nil_node = IR::LiteralNode.new(
              Types::ClassInstance.for("NilClass"), nil, nil, [], convert_loc(location)
            )
            IR::MergeNode.new([branch_node, nil_node], [], convert_loc(location))
          end
        end

        private def merge_case_variables(parent_context, branch_contexts, branches, location)
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
              merge_node = IR::MergeNode.new(merge_branches, [], convert_loc(location))
              parent_context.register_variable(var_name, merge_node)
            elsif merge_branches.size == 1
              parent_context.register_variable(var_name, merge_branches.first)
            end
          end

          # Return MergeNode for the case expression value
          if branches.size > 1
            IR::MergeNode.new(branches.compact.uniq, [], convert_loc(location))
          elsif branches.size == 1
            branches.first
          end
        end

        private def create_nil_literal(location)
          IR::LiteralNode.new(Types::ClassInstance.for("NilClass"), nil, nil, [], convert_loc(location))
        end

        # Check if a node represents a non-returning expression (raise, fail, exit, abort)
        # These should be excluded from branch type inference
        private def non_returning?(node)
          return false unless node.is_a?(IR::CallNode)

          node.receiver.nil? && %i[raise fail exit abort].include?(node.method)
        end

        # Check if a node represents a guard clause body (exits the method)
        # Includes both non-returning expressions (raise/fail) and explicit returns
        private def guard_clause?(node)
          node.is_a?(IR::ReturnNode) || non_returning?(node)
        end

        # After a guard clause (`return/raise unless x`), narrow the guarded variable
        # to remove falsy types (NilClass, FalseClass)
        private def narrow_guard_variable(predicate, kind, context, location)
          case predicate
          when Prism::LocalVariableReadNode
            write_node = context.lookup_variable(predicate.name)
            return unless write_node

            narrow = IR::NarrowNode.new(write_node, kind, write_node.called_methods, convert_loc(location))
            context.register_variable(predicate.name, narrow)
          when Prism::InstanceVariableReadNode
            write_node = context.lookup_instance_variable(predicate.name)
            return unless write_node

            narrow = IR::NarrowNode.new(write_node, kind, write_node.called_methods, convert_loc(location))
            context.narrow_instance_variable(predicate.name, narrow)
          end
        end
      end
    end
  end
end
