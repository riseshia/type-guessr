# frozen_string_literal: true

require "prism"
require_relative "chain"
require_relative "chain_index"
require_relative "chain/link"
require_relative "chain/literal"
require_relative "chain/constant"
require_relative "chain/new_call"
require_relative "chain/variable"
require_relative "chain/call"
require_relative "chain/if"
require_relative "chain/or"
require_relative "literal_type_analyzer"
require_relative "scope_resolver"

module TypeGuessr
  module Core
    # Extracts Chain structures from AST during parsing
    # Replaces ASTAnalyzer with Chain-based extraction
    class ChainExtractor < ::Prism::Visitor
      def initialize(file_path)
        super()
        @file_path = file_path
        @chain_index = ChainIndex.instance
        @scopes = [{}]
        @instance_variables = [{}]
        @class_variables = [{}]
        @class_stack = []
        @method_stack = []
      end

      # Extract chain from local variable assignment
      def visit_local_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column

        register_variable(var_name, line, column)

        if node.value
          chain = extract_chain(node.value)
          store_chain(var_name, line, column, chain) if chain
        end

        super
      end

      # Extract chain from instance variable assignment
      def visit_instance_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column

        register_instance_variable(var_name, line, column)

        if node.value
          chain = extract_chain(node.value)
          store_chain(var_name, line, column, chain) if chain
        end

        super
      end

      # Extract chain from class variable assignment
      def visit_class_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column

        register_class_variable(var_name, line, column)

        if node.value
          chain = extract_chain(node.value)
          store_chain(var_name, line, column, chain) if chain
        end

        super
      end

      # Track method calls for heuristic inference
      def visit_call_node(node)
        track_method_call_on_variable(node) if node.receiver
        super
      end

      # Track class/module definitions for scope
      def visit_class_node(node)
        class_name = extract_class_name(node)
        @class_stack.push(class_name)
        @scopes.push({})
        @instance_variables.push({})
        @class_variables.push({})

        super
      ensure
        @class_stack.pop
        @scopes.pop
        @instance_variables.pop
        @class_variables.pop
      end

      def visit_module_node(node)
        visit_class_node(node)
      end

      # Track method definitions for scope
      def visit_def_node(node)
        method_name = node.name.to_s
        @method_stack.push(method_name)
        @scopes.push({})

        super
      ensure
        @method_stack.pop
        @scopes.pop
      end

      # Parameter visitors - register parameters as variables with optional type inference
      def visit_required_parameter_node(node)
        var_name = node.name.to_s
        location = node.location
        line = location.start_line
        column = location.start_column

        register_variable(var_name, line, column)

        # Store nil chain to mark this variable exists (for method call tracking)
        # This allows find_definitions to find parameter definitions even without a chain
        store_chain(var_name, line, column, nil)

        super
      end

      def visit_optional_parameter_node(node)
        var_name = node.name.to_s
        location = node.location
        line = location.start_line
        column = location.start_column

        register_variable(var_name, line, column)

        # Extract type from default value if present
        if node.value
          chain = extract_chain(node.value)
          store_chain(var_name, line, column, chain) if chain
        end

        super
      end

      def visit_rest_parameter_node(node)
        return super unless node.name

        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_required_keyword_parameter_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_optional_keyword_parameter_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column

        register_variable(var_name, line, column)

        # Extract type from default value if present
        if node.value
          chain = extract_chain(node.value)
          store_chain(var_name, line, column, chain) if chain
        end

        super
      end

      def visit_keyword_rest_parameter_node(node)
        return super unless node.name

        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_block_parameter_node(node)
        return super unless node.name

        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      private

      # Extract a Chain from any expression node
      # @param node [Prism::Node]
      # @return [Chain, nil]
      def extract_chain(node)
        case node
        # Literals
        when Prism::IntegerNode, Prism::FloatNode, Prism::StringNode,
             Prism::InterpolatedStringNode, Prism::SymbolNode,
             Prism::TrueNode, Prism::FalseNode, Prism::NilNode,
             Prism::ArrayNode, Prism::HashNode, Prism::RangeNode,
             Prism::RegularExpressionNode
          extract_literal_chain(node)

        # Variables
        when Prism::LocalVariableReadNode
          Chain.new([Chain::Variable.new(node.name.to_s)])
        when Prism::InstanceVariableReadNode
          Chain.new([Chain::InstanceVariable.new(node.name.to_s)])
        when Prism::ClassVariableReadNode
          Chain.new([Chain::ClassVariable.new(node.name.to_s)])

        # Method calls
        when Prism::CallNode
          extract_call_chain(node)

        # Control flow
        when Prism::IfNode
          extract_if_chain(node)
        when Prism::UnlessNode
          extract_unless_chain(node)
        when Prism::OrNode
          extract_or_chain(node, "||")
        when Prism::AndNode
          extract_or_chain(node, "&&")
        end
      end

      # Extract literal chain using LiteralTypeAnalyzer
      def extract_literal_chain(node)
        type = LiteralTypeAnalyzer.infer(node)
        type ? Chain.new([Chain::Literal.new(type)]) : nil
      end

      # Extract call chain from CallNode
      def extract_call_chain(call_node)
        links = []

        # Walk the chain in reverse (innermost to outermost)
        current = call_node
        while current.is_a?(Prism::CallNode)
          # Check for .new call
          if current.name == :new && current.receiver
            class_name = extract_constant_name(current.receiver)
            if class_name
              args = extract_argument_chains(current.arguments)
              links.unshift(Chain::NewCall.new(class_name, arguments: args))
              return Chain.new(links) # .new terminates chain extraction
            end
          end

          # Regular method call
          has_block = current.block.is_a?(Prism::BlockNode)
          args = extract_argument_chains(current.arguments)
          links.unshift(Chain::Call.new(current.name.to_s, arguments: args, has_block: has_block))

          current = current.receiver
        end

        # Handle the receiver (head of chain)
        head_link = case current
                    when Prism::LocalVariableReadNode
                      Chain::Variable.new(current.name.to_s)
                    when Prism::InstanceVariableReadNode
                      Chain::InstanceVariable.new(current.name.to_s)
                    when Prism::ClassVariableReadNode
                      Chain::ClassVariable.new(current.name.to_s)
                    when Prism::ConstantReadNode, Prism::ConstantPathNode
                      Chain::Constant.new(extract_constant_name(current))
                    when nil
                      # No receiver means this is a method call without explicit receiver
                      # This could be a method call on self, but we don't handle it yet
                      return nil if links.empty?

                      # If there are links, the first one is the method name
                      nil
                    else
                      # Try extracting nested chain for complex receivers
                      nested_chain = extract_chain(current)
                      if nested_chain
                        # Splice nested chain links
                        links = nested_chain.links + links
                        return Chain.new(links)
                      end
                      return nil # Unsupported receiver
                    end

        links.unshift(head_link) if head_link
        links.empty? ? nil : Chain.new(links)
      end

      # Extract argument chains
      def extract_argument_chains(arguments_node)
        return [] unless arguments_node

        arguments_node.arguments.filter_map { |arg| extract_chain(arg) }
      end

      # Extract constant name from node
      def extract_constant_name(node)
        case node
        when Prism::ConstantReadNode
          node.name.to_s
        when Prism::ConstantPathNode
          node.slice
        end
      end

      # Extract if chain
      def extract_if_chain(node)
        condition = extract_chain(node.predicate)
        then_chain = node.statements ? extract_chain_from_statements(node.statements) : nil
        else_chain = if node.subsequent
                       case node.subsequent
                       when Prism::ElseNode
                         node.subsequent.statements ? extract_chain_from_statements(node.subsequent.statements) : nil
                       when Prism::IfNode
                         extract_if_chain(node.subsequent)
                       end
                     end

        Chain.new([Chain::If.new(condition: condition, then_chain: then_chain, else_chain: else_chain)])
      end

      # Extract unless chain (convert to if with swapped branches)
      def extract_unless_chain(node)
        condition = extract_chain(node.predicate)
        then_chain = node.statements ? extract_chain_from_statements(node.statements) : nil
        else_chain = node.else_clause&.statements ? extract_chain_from_statements(node.else_clause.statements) : nil

        # Unless is like if with swapped branches
        Chain.new([Chain::If.new(condition: condition, then_chain: else_chain, else_chain: then_chain)])
      end

      # Extract or/and chain
      def extract_or_chain(node, operator)
        left_chain = extract_chain(node.left)
        right_chain = extract_chain(node.right)

        return nil unless left_chain && right_chain

        Chain.new([Chain::Or.new(left_chain: left_chain, right_chain: right_chain, operator: operator)])
      end

      # Extract chain from last expression in statements
      def extract_chain_from_statements(statements_node)
        return nil unless statements_node.is_a?(Prism::StatementsNode)
        return nil if statements_node.body.empty?

        extract_chain(statements_node.body.last)
      end

      # Store chain in index
      def store_chain(var_name, line, column, chain)
        scope_type = ScopeResolver.determine_scope_type(var_name)
        scope_id = generate_scope_id(scope_type)

        @chain_index.add_chain(
          file_path: @file_path,
          scope_type: scope_type,
          scope_id: scope_id,
          var_name: var_name,
          def_line: line,
          def_column: column,
          chain: chain
        )
      end

      # Track method calls for heuristic inference
      def track_method_call_on_variable(call_node)
        receiver = call_node.receiver
        var_name = case receiver
                   when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
                     receiver.name.to_s
                   end

        return unless var_name

        method_name = call_node.name.to_s
        var_def = find_variable_in_scopes(var_name)
        return unless var_def

        scope_type = var_def[:scope_type]
        scope_id = generate_scope_id(scope_type)

        @chain_index.add_method_call(
          file_path: @file_path,
          scope_type: scope_type,
          scope_id: scope_id,
          var_name: var_name,
          def_line: var_def[:line],
          def_column: var_def[:column],
          method_name: method_name,
          call_line: call_node.location.start_line,
          call_column: call_node.location.start_column
        )
      end

      # Helper methods for scope management (similar to ASTAnalyzer)

      def register_variable(name, line, column)
        @scopes.last[name] = { line: line, column: column, scope_type: :local_variables }
      end

      def register_instance_variable(name, line, column)
        @instance_variables.last[name] = { line: line, column: column, scope_type: :instance_variables }
      end

      def register_class_variable(name, line, column)
        @class_variables.last[name] = { line: line, column: column, scope_type: :class_variables }
      end

      def find_variable_in_scopes(var_name)
        scope_type = ScopeResolver.determine_scope_type(var_name)

        case scope_type
        when :local_variables
          @scopes.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        when :instance_variables
          @instance_variables.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        when :class_variables
          @class_variables.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        end

        nil
      end

      def generate_scope_id(scope_type)
        ScopeResolver.generate_scope_id(scope_type, class_path: current_class_path, method_name: current_method_name)
      end

      def current_class_path
        @class_stack.join("::")
      end

      def current_method_name
        @method_stack.last
      end

      def extract_class_name(node)
        case node
        when Prism::ClassNode, Prism::ModuleNode
          node.constant_path.slice
        end
      end
    end
  end
end
