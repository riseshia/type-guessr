# frozen_string_literal: true

require "prism"
require_relative "types"

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

        # Get type at a specific line and column
        # @param line [Integer] line number (1-based)
        # @param _column [Integer] column number (unused for now)
        # @return [Types::Type] the inferred type
        def type_at(line, _column)
          # Find the most recent type assignment for this line
          # Look backwards from the current line
          (1..line).reverse_each do |l|
            env = @type_env[l]
            next unless env

            # For simplicity, assume we're looking for the first variable in the env
            # In a real implementation, we'd need to know which variable we're looking for
            return env.values.first if env.any?
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
          var_name = node.name.to_s
          current_type = get_type(node.location.start_line - 1, var_name)
          value_type = infer_type_from_node(node.value)

          # For ||= and &&=, create union of existing and new type
          merged_type = if current_type == Types::Unknown.instance
                          value_type
                        else
                          Types::Union.new([current_type, value_type])
                        end

          store_type(node.location.start_line, var_name, merged_type)
          super
        end

        def visit_local_variable_or_write_node(node)
          # Handle ||= operator
          var_name = node.name.to_s
          current_type = get_type(node.location.start_line - 1, var_name)
          value_type = infer_type_from_node(node.value)

          # x ||= y means: x = x || y (x if truthy, else y)
          merged_type = if current_type == Types::Unknown.instance
                          value_type
                        else
                          Types::Union.new([current_type, value_type])
                        end

          store_type(node.location.start_line, var_name, merged_type)
          super
        end

        def visit_local_variable_and_write_node(node)
          # Handle &&= operator
          var_name = node.name.to_s
          current_type = get_type(node.location.start_line - 1, var_name)
          value_type = infer_type_from_node(node.value)

          # x &&= y means: x = x && y (x if falsy, else y)
          merged_type = if current_type == Types::Unknown.instance
                          value_type
                        else
                          Types::Union.new([current_type, value_type])
                        end

          store_type(node.location.start_line, var_name, merged_type)
          super
        end

        def visit_if_node(node)
          # Visit branches and merge types at join point
          then_env = {}
          else_env = {}

          # Collect types from then branch
          if node.statements
            old_env = @type_env.dup
            node.statements.accept(self)
            then_env = extract_env_changes(old_env)
          end

          # Collect types from else branch
          if node.subsequent
            old_env = @type_env.dup
            node.subsequent.accept(self)
            else_env = extract_env_changes(old_env)
          end

          # Merge types at join point
          merge_branches(node.location.end_line, then_env, else_env)

          # Don't call super because we've already visited children
        end

        private

        def infer_type_from_node(node)
          case node
          when Prism::StringNode
            Types::ClassInstance.new("String")
          when Prism::IntegerNode
            Types::ClassInstance.new("Integer")
          when Prism::FloatNode
            Types::ClassInstance.new("Float")
          when Prism::SymbolNode
            Types::ClassInstance.new("Symbol")
          when Prism::ArrayNode
            Types::ArrayType.new
          when Prism::HashNode
            Types::ClassInstance.new("Hash")
          when Prism::TrueNode, Prism::FalseNode
            Types::Union.new([Types::ClassInstance.new("TrueClass"), Types::ClassInstance.new("FalseClass")])
          when Prism::NilNode
            Types::ClassInstance.new("NilClass")
          else
            Types::Unknown.instance
          end
        end

        def store_type(line, var_name, type)
          @type_env[line] ||= {}
          @type_env[line][var_name] = type
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

        def merge_branches(line, then_env, else_env)
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
      end
    end
  end
end
