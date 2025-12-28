# frozen_string_literal: true

require "prism"
require_relative "types"
require_relative "literal_type_analyzer"

module TypeGuessr
  module Core
    # FlowAnalyzer performs flow-sensitive type analysis
    # Analyzes method/block-local type flow for hover support
    class FlowAnalyzer
      # Analyze source code and return analysis result
      # @param source [String] Ruby source code
      # @return [AnalysisResult] analysis result with type information
      def analyze(source)
        parsed = Prism.parse(source)
        visitor = FlowVisitor.new
        parsed.value.accept(visitor)
        AnalysisResult.new(visitor.type_env, visitor.return_types)
      end

      # AnalysisResult holds the results of flow analysis
      class AnalysisResult
        def initialize(type_env, return_types)
          @type_env = type_env # { line => { var_name => type } }
          @return_types = return_types # { method_name => type }
        end

        # Get type at a specific line and column for a specific variable
        # @param line [Integer] line number (1-based)
        # @param _column [Integer] column number (unused for now)
        # @param var_name [String] variable name to look up
        # @return [Types::Type] the inferred type
        def type_at(line, _column, var_name)
          # Find the most recent type assignment for this variable
          # Look backwards from the current line
          (1..line).reverse_each do |l|
            env = @type_env[l]
            next unless env

            # Look for the specific variable
            return env[var_name] if env.key?(var_name)
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

      # FlowVisitor traverses AST and tracks type flow
      class FlowVisitor < Prism::Visitor
        attr_reader :type_env, :return_types

        def initialize
          super
          @type_env = {} # { line => { var_name => type } }
          @return_types = {} # { method_name => type }
          @current_method = nil
          @method_returns = [] # Collect return types for current method
        end

        def visit_def_node(node)
          old_method = @current_method
          old_returns = @method_returns

          @current_method = node.name.to_s
          @method_returns = []

          super

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
          else
            # Try literal type inference
            type = LiteralTypeAnalyzer.infer(node)
            type || Types::Unknown.instance
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
          (1..line).reverse_each do |l|
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
