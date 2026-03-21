# frozen_string_literal: true

require "prism"
require_relative "context"
require_relative "literal_converter"
require_relative "variable_converter"
require_relative "container_mutation_converter"
require_relative "../ir"
require_relative "../types"

module TypeGuessr
  module Core
    module Converter
      # Converts Prism AST to IR graph (reverse dependency graph)
      # Each IR node points to nodes it depends on
      class PrismConverter
        def initialize
          @literal_type_cache = {}
        end

        # Convert Prism AST to IR graph
        # @param prism_node [Prism::Node] Prism AST node
        # @param context [Context] Conversion context
        # @return [IR::Node, nil] IR node
        def convert(prism_node, context = Context.new)
          node = case prism_node
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

                 when Prism::KeywordHashNode
                   convert_keyword_hash(prism_node, context)

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
                   # Unwrap visibility modifier: `private def foo` → treat as `def foo`
                   if visibility_modifier_with_def?(prism_node)
                     convert_def(prism_node.arguments.arguments.first, context,
                                 module_function: prism_node.name == :module_function)
                   else
                     convert_call(prism_node, context)
                   end

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
                                    Types::ClassInstance.for("NilClass"),
                                    nil,
                                    nil,
                                    [],
                                    convert_loc(prism_node.location)
                                  )
                                end
                   IR::ReturnNode.new(
                     value_node,
                     [],
                     convert_loc(prism_node.location)
                   )

                 when Prism::SelfNode
                   # self keyword - returns the current class instance or singleton
                   IR::SelfNode.new(
                     context.current_class_name || "Object",
                     context.in_singleton_method,
                     [],
                     convert_loc(prism_node.location)
                   )

                 when Prism::BeginNode
                   convert_begin(prism_node, context)

                 when Prism::RescueNode
                   # Rescue clause - convert body statements
                   convert_statements_body(prism_node.statements&.body, context)

                 when Prism::OrNode
                   convert_or_node(prism_node, context)

                 when Prism::AndNode
                   convert_and_node(prism_node, context)

                 when Prism::IndexOrWriteNode
                   convert_index_or_write(prism_node, context)

                 when Prism::ParenthesesNode
                   convert(prism_node.body, context) if prism_node.body

                 when Prism::MultiWriteNode
                   convert_multi_write(prism_node, context)
                 end

          register_node(node, context) if node
          node
        end

        private def convert_call(prism_node, context)
          # Convert receiver - if nil and inside a class, create implicit SelfNode
          receiver_node = if prism_node.receiver
                            convert(prism_node.receiver, context)
                          elsif context.current_class_name
                            IR::SelfNode.new(
                              context.current_class_name,
                              context.in_singleton_method,
                              [],
                              convert_loc(prism_node.location)
                            )
                          end

          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []

          has_block = !prism_node.block.nil?

          # Track method call on receiver for method-based type inference
          if variable_node?(receiver_node) && receiver_node.called_methods.none? { |cm| cm.name == prism_node.name }
            receiver_node.called_methods << build_called_method(prism_node)
          end

          # Handle container mutating methods (Hash#[]=, Array#[]=, Array#<<)
          receiver_node = handle_container_mutation(prism_node, receiver_node, args, context) if container_mutating_method?(prism_node.name, receiver_node)

          # Use message_loc for method name position to match hover lookup
          call_loc = convert_loc(prism_node.message_loc || prism_node.location)
          call_node = IR::CallNode.new(
            prism_node.name, receiver_node, args, [], nil, has_block, [], call_loc
          )

          # Handle block if present (but not block arguments like &block)
          if prism_node.block.is_a?(Prism::BlockNode)
            block_body = convert_block(prism_node.block, call_node, context)
            # Update block_body and has_block on mutable Struct
            call_node.block_body = block_body
            call_node.has_block = true
          end

          call_node
        end

        # Check if node is any variable node (for method call tracking)
        private def variable_node?(node)
          node.is_a?(IR::LocalWriteNode) ||
            node.is_a?(IR::LocalReadNode) ||
            node.is_a?(IR::InstanceVariableWriteNode) ||
            node.is_a?(IR::InstanceVariableReadNode) ||
            node.is_a?(IR::ClassVariableWriteNode) ||
            node.is_a?(IR::ClassVariableReadNode) ||
            node.is_a?(IR::ParamNode) ||
            node.is_a?(IR::BlockParamSlot)
        end

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

        # Build CalledMethod with signature information from Prism CallNode
        private def build_called_method(prism_node)
          positional_count, has_splat, keywords = extract_call_signature(prism_node)

          IR::CalledMethod.new(
            name: prism_node.name,
            positional_count: has_splat ? nil : positional_count,
            keywords: keywords
          )
        end

        # Extract positional count, splat presence, and keywords from call arguments
        # @return [Array(Integer, Boolean, Array<Symbol>)] [positional_count, has_splat, keywords]
        private def extract_call_signature(prism_node)
          arguments = prism_node.arguments&.arguments || []
          positional_count = 0
          has_splat = false
          keywords = []

          arguments.each do |arg|
            case arg
            when Prism::SplatNode
              has_splat = true
            when Prism::KeywordHashNode
              extract_keywords_from_hash(arg, keywords)
            else
              positional_count += 1
            end
          end

          [positional_count, has_splat, keywords]
        end

        # Extract keyword argument names from KeywordHashNode
        private def extract_keywords_from_hash(hash_node, keywords)
          hash_node.elements.each do |element|
            next unless element.is_a?(Prism::AssocNode)

            key = element.key
            keywords << key.value.to_sym if key.is_a?(Prism::SymbolNode)
          end
        end

        # Extract IR param nodes from a Prism parameter node
        # Handles destructuring (MultiTargetNode) by flattening nested params
        private def extract_param_nodes(param, kind, context, default_value: nil)
          case param
          when Prism::MultiTargetNode
            # Destructuring parameter like (a, b) - extract all nested params
            param.lefts.flat_map { |p| extract_param_nodes(p, kind, context) } +
              param.rights.flat_map { |p| extract_param_nodes(p, kind, context) }
          when Prism::RequiredParameterNode, Prism::OptionalParameterNode
            param_node = IR::ParamNode.new(param.name, kind, default_value, [], convert_loc(param.location))
            context.register_variable(param.name, param_node)
            [param_node]
          else
            []
          end
        end

        private def convert_block(block_node, call_node, context)
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

                slot = IR::BlockParamSlot.new(index, call_node, [], convert_loc(param_loc))
                call_node.block_params << slot
                block_context.register_variable(param_name, slot)
              end
            end
          end

          # Convert block body and return it for block return type inference
          block_node.body ? convert(block_node.body, block_context) : nil
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

        private def convert_def(prism_node, context, module_function: false)
          def_context = context.fork(:method)
          def_context.current_method = prism_node.name.to_s
          def_context.in_singleton_method = prism_node.receiver.is_a?(Prism::SelfNode)

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
              param_node = IR::ParamNode.new(param.name, :optional, default_node, [], convert_loc(param.location))
              params << param_node
              def_context.register_variable(param.name, param_node)
            end

            # Rest parameter (*args)
            if parameters_node.rest.is_a?(Prism::RestParameterNode)
              rest = parameters_node.rest
              param_node = IR::ParamNode.new(rest.name || :*, :rest, nil, [], convert_loc(rest.location))
              params << param_node
              def_context.register_variable(rest.name, param_node) if rest.name
            end

            # Required keyword parameters (name:)
            parameters_node.keywords&.each do |kw|
              case kw
              when Prism::RequiredKeywordParameterNode
                param_node = IR::ParamNode.new(kw.name, :keyword_required, nil, [], convert_loc(kw.location))
                params << param_node
                def_context.register_variable(kw.name, param_node)
              when Prism::OptionalKeywordParameterNode
                default_node = convert(kw.value, def_context)
                param_node = IR::ParamNode.new(kw.name, :keyword_optional, default_node, [], convert_loc(kw.location))
                params << param_node
                def_context.register_variable(kw.name, param_node)
              end
            end

            # Keyword rest parameter (**kwargs)
            if parameters_node.keyword_rest.is_a?(Prism::KeywordRestParameterNode)
              kwrest = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(kwrest.name || :**, :keyword_rest, nil, [], convert_loc(kwrest.location))
              params << param_node
              def_context.register_variable(kwrest.name, param_node) if kwrest.name
            elsif parameters_node.keyword_rest.is_a?(Prism::ForwardingParameterNode)
              # Forwarding parameter (...)
              fwd = parameters_node.keyword_rest
              param_node = IR::ParamNode.new(:"...", :forwarding, nil, [], convert_loc(fwd.location))
              params << param_node
            end

            # Block parameter (&block)
            if parameters_node.block
              block = parameters_node.block
              param_node = IR::ParamNode.new(block.name || :&, :block, nil, [], convert_loc(block.location))
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
            prism_node.name,
            def_context.current_class_name,
            params,
            return_node,
            body_nodes,
            [],
            convert_loc(prism_node.name_loc),
            prism_node.receiver.is_a?(Prism::SelfNode),
            module_function: module_function
          )
        end

        # Compute the return node for a method by collecting all return points
        # @param body_nodes [Array<IR::Node>] All nodes in the method body
        # @param loc [Prism::Location] Location for the MergeNode if needed
        # @return [IR::Node, nil] The return node (MergeNode if multiple returns)
        private def compute_return_node(body_nodes, loc)
          return nil if body_nodes.empty?

          # Collect all explicit returns from the body
          explicit_returns = collect_returns(body_nodes)

          # The implicit return is the last non-ReturnNode in body
          implicit_return = body_nodes.grep_v(IR::ReturnNode).last

          # Determine all return points
          return_points = explicit_returns.dup
          return_points << implicit_return if implicit_return && !last_node_returns?(body_nodes)

          case return_points.size
          when 0
            nil
          when 1
            return_points.first
          else
            IR::MergeNode.new(return_points, [], convert_loc(loc))
          end
        end

        # Collect all ReturnNode instances from body nodes (recursive)
        # Searches inside MergeNode branches to find nested returns from if/case
        # @param nodes [Array<IR::Node>] Nodes to search
        # @return [Array<IR::ReturnNode>] All explicit return nodes
        private def collect_returns(nodes)
          returns = []
          nodes.each do |node|
            case node
            when IR::ReturnNode
              returns << node
            when IR::MergeNode
              returns.concat(collect_returns(node.branches))
            when IR::OrNode
              returns.concat(collect_returns([node.lhs, node.rhs]))
            end
          end
          returns
        end

        # Check if the last node in body is a ReturnNode
        # @param body_nodes [Array<IR::Node>] Body nodes
        # @return [Boolean]
        private def last_node_returns?(body_nodes)
          body_nodes.last.is_a?(IR::ReturnNode)
        end

        private def convert_constant_read(prism_node, context)
          name = case prism_node
                 when Prism::ConstantReadNode
                   prism_node.name.to_s
                 when Prism::ConstantPathNode
                   prism_node.slice
                 else
                   prism_node.to_s
                 end

          IR::ConstantNode.new(name, context.lookup_constant(name), [], convert_loc(prism_node.location))
        end

        private def convert_constant_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          context.register_constant(prism_node.name.to_s, value_node)
          IR::ConstantNode.new(prism_node.name.to_s, value_node, [], convert_loc(prism_node.location))
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

        private def convert_class_or_module(prism_node, context)
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

          IR::ClassModuleNode.new(name, methods, [], convert_loc(prism_node.constant_path&.location || prism_node.location))
        end

        private def convert_singleton_class(prism_node, context)
          # Create a new context for singleton class scope
          singleton_context = context.fork(:class)

          # Generate singleton class name in format: Parent::<Class:ParentName>
          # This matches the scope convention used by RuntimeAdapter and RubyIndexer
          parent_path = context.current_class_name || ""
          parent_name = IR.extract_last_name(parent_path) || "Object"
          singleton_suffix = "<Class:#{parent_name}>"
          singleton_name = parent_path.empty? ? singleton_suffix : "#{parent_path}::#{singleton_suffix}"
          singleton_context.current_class = singleton_name

          # Collect all method definitions from the body
          methods = []
          if prism_node.body.is_a?(Prism::StatementsNode)
            prism_node.body.body.each do |stmt|
              node = convert(stmt, singleton_context)
              methods << node if node.is_a?(IR::DefNode)
            end
          end

          IR::ClassModuleNode.new(singleton_name, methods, [], convert_loc(prism_node.location))
        end

        private def convert_loc(prism_location)
          prism_location.start_offset
        end

        # Register node in location_index and registries during conversion
        # This eliminates the need for a separate tree traversal after conversion
        private def register_node(node, context)
          return unless context.location_index

          case node
          when IR::DefNode
            # DefNode uses singleton-adjusted method_scope for registration
            method_scope = singleton_scope_for(context.current_class_name || "", singleton: node.singleton)
            context.location_index.add(context.file_path, node, method_scope)
            register_method(node, context)

            # Register params (created directly, not via convert)
            # Use method scope with method name for params
            param_scope = method_scope.empty? ? "##{node.name}" : "#{method_scope}##{node.name}"
            node.params&.each do |param|
              context.location_index.add(context.file_path, param, param_scope)
            end
          when IR::ClassModuleNode
            # ClassModuleNode uses parent scope for registration
            context.location_index.add(context.file_path, node, context.scope_id)
            register_class_module(node, context)
          when IR::CallNode
            context.location_index.add(context.file_path, node, context.scope_id)
            # Register block params (created directly, not via convert)
            node.block_params&.each do |param|
              context.location_index.add(context.file_path, param, context.scope_id)
            end
          when IR::InstanceVariableWriteNode
            context.location_index.add(context.file_path, node, context.scope_id)
            context.ivar_registry&.register(node.class_name, node.name, node, file_path: context.file_path)
          when IR::ClassVariableWriteNode
            context.location_index.add(context.file_path, node, context.scope_id)
            context.cvar_registry&.register(node.class_name, node.name, node, file_path: context.file_path)
          else
            # All other nodes (MergeNode, LiteralNode, etc.)
            context.location_index.add(context.file_path, node, context.scope_id)
          end
        end

        # Register method in method_registry
        # Only registers top-level methods; class methods are handled by register_class_module
        private def register_method(node, context)
          return unless context.method_registry

          # Only register top-level methods (no class context)
          return unless (context.current_class_name || "").empty?

          context.method_registry.register("", node.name.to_s, node, file_path: context.file_path)
        end

        # Register methods from a class/module in method_registry
        private def register_class_module(node, context)
          return unless context.method_registry

          # Build the full class path from parent context + node name
          parent_path = context.current_class_name || ""
          class_path = parent_path.empty? ? node.name : "#{parent_path}::#{node.name}"

          # Register each method in the class (nested classes are handled recursively via convert)
          node.methods&.each do |method|
            next if method.is_a?(IR::ClassModuleNode)

            method_scope = singleton_scope_for(class_path, singleton: method.singleton)
            context.method_registry.register(method_scope, method.name.to_s, method, file_path: context.file_path)

            # module_function: also register as singleton method
            if method.module_function
              singleton_scope = singleton_scope_for(class_path, singleton: true)
              context.method_registry.register(singleton_scope, method.name.to_s, method, file_path: context.file_path)
            end
          end
        end

        # Build singleton class scope for method registration/lookup
        # Singleton methods use "<Class:ClassName>" suffix to match RubyIndexer convention
        # @param scope [String] Base scope (e.g., "RBS::Environment")
        # @param singleton [Boolean] Whether the method is a singleton method
        # @return [String] Scope with singleton class suffix if applicable
        private def singleton_scope_for(scope, singleton:)
          return scope unless singleton

          parent_name = IR.extract_last_name(scope) || "Object"
          scope.empty? ? "<Class:Object>" : "#{scope}::<Class:#{parent_name}>"
        end

        # Check if a CallNode is a visibility modifier wrapping a def (e.g., `private def foo`)
        private def visibility_modifier_with_def?(prism_node)
          %i[private protected public module_function].include?(prism_node.name) &&
            prism_node.receiver.nil? &&
            prism_node.arguments&.arguments&.size == 1 &&
            prism_node.arguments.arguments.first.is_a?(Prism::DefNode)
        end
      end
    end
  end
end
