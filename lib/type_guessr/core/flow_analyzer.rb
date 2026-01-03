# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "literal_type_analyzer"
require_relative "rbs_provider"
require_relative "chain_index"
require_relative "chain/literal"

module TypeGuessr
  module Core
    # FlowAnalyzer performs flow-sensitive type analysis
    # Analyzes method/block-local type flow for hover support
    class FlowAnalyzer
      # Initialize FlowAnalyzer with optional initial type information
      # @param initial_types [Hash{String => Types::Type}] initial type information for variables
      def initialize(initial_types: {})
        @initial_types = initial_types
      end

      # Analyze source code and return analysis result
      # @param source [String] Ruby source code
      # @return [AnalysisResult] analysis result with type information
      def analyze(source)
        parsed = Prism.parse(source)
        visitor = FlowVisitor.new(@initial_types)
        parsed.value.accept(visitor)
        AnalysisResult.new(visitor.type_env, visitor.return_types, visitor.scope_snapshots)
      end

      # AnalysisResult holds the results of flow analysis
      class AnalysisResult
        def initialize(type_env, return_types, scope_snapshots = [])
          @type_env = type_env # { line => { var_name => type } }
          @return_types = return_types # { method_name => type }
          @scope_snapshots = scope_snapshots # Array of completed scopes
        end

        # Get type at a specific line and column for a specific variable
        # @param line [Integer] line number (1-based)
        # @param _column [Integer] column number (unused for now)
        # @param var_name [String] variable name to look up
        # @return [Types::Type] the inferred type
        def type_at(line, _column, var_name)
          # First check scope snapshots (for block parameters and scoped variables)
          # Find all scopes that contain this line
          applicable_scopes = @scope_snapshots.select do |scope|
            line.between?(scope.start_line, scope.end_line)
          end.sort_by(&:start_line).reverse # Innermost first

          # Check scopes from innermost to outermost
          applicable_scopes.each do |scope|
            type = scope.lookup(var_name)
            return type if type
          end

          # Fallback to line-based lookup for backward compatibility
          # But skip variables that are in block scopes that don't contain the current line
          (1..line).reverse_each do |l|
            env = @type_env[l]
            next unless env
            next unless env.key?(var_name)

            # Check if this line is inside a block scope that doesn't contain the current line
            # If so, skip this variable (it's a block-local variable)
            in_inapplicable_block = @scope_snapshots.any? do |scope|
              scope.kind == :block &&
                l.between?(scope.start_line, scope.end_line) &&
                !line.between?(scope.start_line, scope.end_line) &&
                scope.binding?(var_name)
            end

            return env[var_name] unless in_inapplicable_block
          end

          Types::Unknown.instance
        end

        # Get return type for a method
        # @param method_name [String] method name
        # @return [Types::Type] the inferred return type
        def return_type_for_method(method_name)
          @return_types[method_name] || Types::Unknown.instance
        end
      end

      # Scope represents a lexical scope (method, block, etc.) for type tracking
      class Scope
        attr_reader :types, :start_line, :kind
        attr_accessor :end_line

        # Initialize a new scope
        # @param start_line [Integer] the starting line number of the scope
        # @param kind [Symbol] the kind of scope (:root, :method, :block)
        def initialize(start_line:, kind:)
          @types = {} # { var_name => type }
          @start_line = start_line
          @end_line = nil # Set when scope is closed
          @kind = kind
        end

        # Bind a variable to a type in this scope
        # @param var_name [String] the variable name
        # @param type [Types::Type] the type
        def bind(var_name, type)
          @types[var_name] = type
        end

        # Look up a variable's type in this scope
        # @param var_name [String] the variable name
        # @return [Types::Type, nil] the type or nil if not found
        def lookup(var_name)
          @types[var_name]
        end

        # Check if a variable is bound in this scope
        # @param var_name [String] the variable name
        # @return [Boolean] true if the variable is bound in this scope
        def binding?(var_name)
          @types.key?(var_name)
        end
      end

      # FlowVisitor traverses AST and tracks type flow
      class FlowVisitor < Prism::Visitor
        attr_reader :type_env, :return_types, :scope_snapshots

        # Initialize visitor with optional initial type information
        # @param initial_types [Hash{String => Types::Type}] initial type information
        def initialize(initial_types = {})
          super()
          @type_env = {} # { line => { var_name => type } } - kept for backward compatibility
          @return_types = {} # { method_name => type }
          @current_method = nil
          @method_returns = [] # Collect return types for current method
          @initial_types = initial_types
          @scope_stack = [] # Active scope stack
          @scope_snapshots = [] # Completed scopes for type_at

          # Store initial types at line 0 for lookups (backward compatibility)
          @type_env[0] = initial_types.dup if initial_types.any?

          # Create root scope with initial types
          push_scope(start_line: 0, kind: :root)
          initial_types.each { |var_name, type| bind_in_current_scope(var_name, type) }
        end

        def visit_def_node(node)
          old_method = @current_method
          old_returns = @method_returns

          @current_method = node.name.to_s
          @method_returns = []

          # Push method scope
          push_scope(start_line: node.location.start_line, kind: :method)

          super

          # Pop method scope
          pop_scope(end_line: node.location.end_line)

          # Add implicit return from last expression
          if node.body.is_a?(Prism::StatementsNode) && node.body.body.any?
            last_expr = node.body.body.last
            last_type = infer_type_from_node(last_expr)
            @method_returns << last_type unless last_type == Types::Unknown.instance
          elsif node.body.nil? || (node.body.is_a?(Prism::StatementsNode) && node.body.body.empty?)
            # Empty method body returns nil implicitly
            @method_returns << Types::ClassInstance.new("NilClass")
          end

          # Infer return type from collected returns
          if @method_returns.any?
            return_type = if @method_returns.size == 1
                            @method_returns.first
                          else
                            Types::Union.new(@method_returns)
                          end
            @return_types[@current_method] = return_type
          end

          @current_method = old_method
          @method_returns = old_returns
        end

        def visit_return_node(node)
          if @current_method && node.arguments
            type = infer_type_from_node(node.arguments.arguments.first)
            @method_returns << type
          end
          super
        end

        def visit_call_node(node)
          # If the call has a block, push block scope before visiting
          has_block_scope = false

          if node.block.is_a?(Prism::BlockNode)
            block = node.block

            # Infer receiver type and get block parameter types
            receiver_type = node.receiver ? infer_type_from_node(node.receiver) : Types::Unknown.instance
            class_name = extract_class_name(receiver_type)
            method_name = node.name.to_s

            if class_name
              # Get element type for Array receiver
              elem_type = extract_element_type(receiver_type)

              # Get block parameter types from RBS
              param_types = RBSProvider.instance.get_block_param_types_with_substitution(
                class_name, method_name, elem: elem_type
              )

              # Push block scope and bind parameters
              push_scope(start_line: block.location.start_line, kind: :block)
              bind_block_params(block.parameters, param_types) if block.parameters && param_types
              has_block_scope = true
            end
          end

          super

          # Pop block scope after visiting
          pop_scope(end_line: node.block.location.end_line) if has_block_scope
        rescue StandardError
          # Pop scope if we pushed one
          pop_scope(end_line: node.block.location.end_line) if has_block_scope
          super
        end

        def visit_local_variable_write_node(node)
          var_name = node.name.to_s
          value_type = infer_type_from_node(node.value)

          store_type(node.location.start_line, var_name, value_type)
          super
        end

        def visit_local_variable_operator_write_node(node)
          handle_compound_assignment(node)
          super
        end

        def visit_local_variable_or_write_node(node)
          handle_compound_assignment(node)
          super
        end

        def visit_local_variable_and_write_node(node)
          handle_compound_assignment(node)
          super
        end

        def visit_if_node(node)
          # Visit branches and merge types at join point
          # Keep all branch-local types in @type_env, and add merged types at join point
          then_vars = {}
          else_vars = {}

          # Save environment before visiting branches
          saved_env = deep_copy_env(@type_env)

          # Visit then branch - types are stored directly in @type_env
          if node.statements
            node.statements.accept(self)
            then_vars = extract_env_changes(saved_env)
          end

          # Save the state after then branch
          after_then_env = deep_copy_env(@type_env)

          # Reset to before if, then visit else branch
          @type_env = deep_copy_env(saved_env)

          # Visit else branch - types are stored directly in @type_env
          if node.subsequent
            node.subsequent.accept(self)
            else_vars = extract_env_changes(saved_env)
          else
            # No else branch means variables keep their original types
            # Extract original types for variables that changed in then branch
            then_vars.each_key do |var|
              # Find the type this variable had before the if
              original_type = find_type_in_env(saved_env, var)
              else_vars[var] = original_type if original_type
            end
          end

          # Merge the two branch environments
          # Take all lines from both branches and merge them
          @type_env = merge_branch_envs(after_then_env, @type_env, saved_env)

          # Add merged types at the join point
          merge_branches(node.location.end_line, then_vars, else_vars, saved_env)

          # Don't call super because we've already visited children
        end

        private

        # Scope management methods

        # Push a new scope onto the scope stack
        # @param start_line [Integer] the starting line of the scope
        # @param kind [Symbol] the kind of scope (:root, :method, :block)
        def push_scope(start_line:, kind:)
          scope = Scope.new(start_line: start_line, kind: kind)
          @scope_stack.push(scope)
        end

        # Pop the current scope from the stack and save it to snapshots
        # @param end_line [Integer] the ending line of the scope
        # @return [Scope] the popped scope
        def pop_scope(end_line:)
          scope = @scope_stack.pop
          scope.end_line = end_line
          @scope_snapshots << scope
          scope
        end

        # Get the current (innermost) scope
        # @return [Scope, nil] the current scope or nil if stack is empty
        def current_scope
          @scope_stack.last
        end

        # Bind a variable to a type in the current scope
        # @param var_name [String] the variable name
        # @param type [Types::Type] the type
        def bind_in_current_scope(var_name, type)
          current_scope&.bind(var_name, type)
        end

        # Look up a variable through the scope chain
        # @param var_name [String] the variable name
        # @return [Types::Type] the type or Unknown if not found
        def lookup_through_scopes(var_name)
          @scope_stack.reverse_each do |scope|
            return scope.lookup(var_name) if scope.binding?(var_name)
          end
          Types::Unknown.instance
        end

        # Type inference and assignment methods

        def handle_compound_assignment(node)
          var_name = node.name.to_s
          current_type = get_type(node.location.start_line - 1, var_name)
          value_type = infer_type_from_node(node.value)

          merged_type = if current_type == Types::Unknown.instance
                          value_type
                        else
                          Types::Union.new([current_type, value_type])
                        end

          store_type(node.location.start_line, var_name, merged_type)
        end

        def infer_type_from_node(node)
          # Handle special flow-sensitive cases first
          case node
          when Prism::TrueNode, Prism::FalseNode
            # FlowAnalyzer-specific: treat boolean literals as union
            Types::Union.new([Types::ClassInstance.new("TrueClass"), Types::ClassInstance.new("FalseClass")])
          when Prism::IfNode
            infer_if_expression_type(node)
          when Prism::CallNode
            infer_call_node_type(node)
          when Prism::LocalVariableReadNode
            # Look up variable type from current environment
            get_type(node.location.start_line, node.name.to_s)
          else
            # Try literal type inference
            type = LiteralTypeAnalyzer.infer(node)
            type || Types::Unknown.instance
          end
        end

        # Infer the type of a call node by analyzing receiver and method
        # @param node [Prism::CallNode] the call node
        # @return [Types::Type] the inferred type
        def infer_call_node_type(node)
          return Types::Unknown.instance unless node.receiver

          # Infer receiver type
          receiver_type = infer_type_from_node(node.receiver)
          return Types::Unknown.instance if receiver_type == Types::Unknown.instance

          # Extract class name from receiver type
          class_name = extract_class_name(receiver_type)
          return Types::Unknown.instance unless class_name

          method_name = node.name.to_s

          # Check if there's a block
          if node.block.is_a?(Prism::BlockNode)
            infer_call_with_block(node, class_name, method_name, receiver_type)
          else
            # 1. Try RBS first
            rbs_type = RBSProvider.instance.get_method_return_type(class_name, method_name)
            return rbs_type if rbs_type && rbs_type != Types::Unknown.instance

            # 2. Try ChainIndex for user-defined methods
            infer_from_chain_index(class_name, method_name)
          end
        rescue StandardError
          Types::Unknown.instance
        end

        # Infer type from ChainIndex for user-defined methods
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @return [Types::Type] the inferred type
        def infer_from_chain_index(class_name, method_name)
          chains = ChainIndex.instance.get_method_return_chains(class_name, method_name)
          return Types::Unknown.instance if chains.empty?

          # Collect all types from chains
          types = []
          chains.each do |chain|
            # For simple cases (single literal return), extract type directly
            return Types::Unknown.instance unless chain.links.size == 1 && chain.links.first.is_a?(Chain::Literal)

            types << chain.links.first.type

            # For complex cases, we can't resolve without full ChainContext
            # Return Unknown to avoid incorrect inference
          end

          return Types::Unknown.instance if types.empty?

          # If all return paths have the same type, return it
          return types.first if types.uniq.size == 1

          # Multiple different types -> create Union
          Types::Union.new(types.uniq)
        end

        # Extract class name from a type object
        # @param type [Types::Type] the type object
        # @return [String, nil] the class name or nil
        def extract_class_name(type)
          case type
          when Types::ClassInstance
            type.name
          when Types::ArrayType
            "Array"
          when Types::HashShape
            "Hash"
          end
        end

        # Infer the type of an if expression by analyzing both branches
        # @param node [Prism::IfNode] the if node
        # @return [Types::Type] the inferred type
        def infer_if_expression_type(node)
          then_type = if node.statements&.body&.any?
                        infer_type_from_node(node.statements.body.last)
                      else
                        Types::ClassInstance.new("NilClass")
                      end

          else_type = if node.subsequent
                        case node.subsequent
                        when Prism::ElseNode
                          if node.subsequent.statements&.body&.any?
                            infer_type_from_node(node.subsequent.statements.body.last)
                          else
                            Types::ClassInstance.new("NilClass")
                          end
                        when Prism::IfNode
                          # elsif branch
                          infer_if_expression_type(node.subsequent)
                        else
                          Types::Unknown.instance
                        end
                      else
                        Types::ClassInstance.new("NilClass")
                      end

          # Return union of both branch types
          if then_type == else_type
            then_type
          else
            Types::Union.new([then_type, else_type])
          end
        end

        # Infer the type of a method call with a block
        # @param node [Prism::CallNode] the call node
        # @param class_name [String] the receiver class name
        # @param method_name [String] the method name
        # @param receiver_type [Types::Type] the receiver type
        # @return [Types::Type] the inferred return type
        def infer_call_with_block(node, class_name, method_name, receiver_type)
          block = node.block

          # 1. Extract element type from receiver (for Array)
          elem_type = extract_element_type(receiver_type)

          # 2. Get block parameter types from RBS
          param_types = RBSProvider.instance.get_block_param_types_with_substitution(
            class_name, method_name, elem: elem_type
          )

          # 3. Push block scope
          push_scope(start_line: block.location.start_line, kind: :block)

          # 4. Bind block parameters to their types
          bind_block_params(block.parameters, param_types) if block.parameters

          # 5. Analyze block body to infer return type
          block_return_type = infer_block_return_type(block)

          # 6. Pop block scope (parameters no longer visible outside block)
          pop_scope(end_line: block.location.end_line)

          # 7. Get method return type with substitution
          substitutions = { U: block_return_type, Elem: elem_type }.compact
          RBSProvider.instance.get_method_return_type_with_substitution(
            class_name, method_name, substitutions
          )
        rescue StandardError
          Types::Unknown.instance
        end

        # Extract element type from Array type
        # @param type [Types::Type] the type
        # @return [Types::Type, nil] the element type or nil
        def extract_element_type(type)
          case type
          when Types::ArrayType
            type.element_type
          end
        end

        # Bind block parameters to their types
        # @param params_node [Prism::BlockParametersNode, nil] the block parameters node
        # @param param_types [Array<Types::Type>] the parameter types
        def bind_block_params(params_node, param_types)
          return unless params_node
          return unless params_node.parameters

          required_params = params_node.parameters.requireds
          required_params.each_with_index do |param, index|
            # Extract parameter name
            param_name = case param
                         when Prism::RequiredParameterNode
                           param.name.to_s
                         when Prism::MultiTargetNode
                           # Skip complex parameter patterns
                           next
                         else
                           next
                         end

            # Assign type to parameter
            param_type = param_types[index] || Types::Unknown.instance

            # Bind in current (block) scope
            bind_in_current_scope(param_name, param_type)

            # Also store in line-based env for backward compatibility
            store_type(param.location.start_line, param_name, param_type)
          end
        end

        # Infer the return type of a block
        # @param block [Prism::BlockNode] the block node
        # @return [Types::Type] the inferred return type
        def infer_block_return_type(block)
          # Empty block returns NilClass
          return Types::ClassInstance.new("NilClass") if block.body.nil?

          # Get block body statements
          body = block.body
          statements = body.is_a?(Prism::StatementsNode) ? body.body : [body]

          return Types::ClassInstance.new("NilClass") if statements.empty?

          # Analyze last expression
          last_expr = statements.last
          infer_type_from_node(last_expr)
        end

        def store_type(line, var_name, type)
          @type_env[line] ||= {}
          @type_env[line][var_name] = type
        end

        def deep_copy_env(env)
          # Create a deep copy of the environment
          env.transform_values(&:dup)
        end

        def find_type_in_env(env, var_name)
          # Find the most recent type for a variable in the environment
          env.keys.sort.reverse.each do |line|
            return env[line][var_name] if env[line]&.key?(var_name)
          end
          nil
        end

        def get_type(line, var_name)
          # Look backwards from line to find most recent type
          # Include line 0 for initial types
          (0..line).reverse_each do |l|
            env = @type_env[l]
            return env[var_name] if env&.key?(var_name)
          end
          Types::Unknown.instance
        end

        def extract_env_changes(old_env)
          changes = {}
          @type_env.each do |line, env|
            next if old_env[line] == env

            env.each do |var, type|
              changes[var] = type
            end
          end
          changes
        end

        def merge_branches(line, then_env, else_env, _saved_env = nil)
          all_vars = (then_env.keys + else_env.keys).uniq

          all_vars.each do |var|
            then_type = then_env[var] || Types::Unknown.instance
            else_type = else_env[var] || Types::Unknown.instance

            merged_type = if then_type == else_type
                            then_type
                          else
                            Types::Union.new([then_type, else_type])
                          end

            store_type(line, var, merged_type)
          end
        end

        # Merge two branch environments, keeping types from both branches
        # @param then_env [Hash] environment from then branch
        # @param else_env [Hash] environment from else branch
        # @param base_env [Hash] environment before the if
        # @return [Hash] merged environment
        def merge_branch_envs(then_env, else_env, base_env)
          # Start with the base environment
          result = deep_copy_env(base_env)

          # Add all lines from then branch
          then_env.each do |line, vars|
            result[line] ||= {}
            result[line].merge!(vars)
          end

          # Add all lines from else branch
          else_env.each do |line, vars|
            result[line] ||= {}
            result[line].merge!(vars)
          end

          result
        end
      end
    end
  end
end
