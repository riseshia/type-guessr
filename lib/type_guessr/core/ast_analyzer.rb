# frozen_string_literal: true

require "prism"
require_relative "scope_resolver"
require_relative "variable_index"
require_relative "types"
require_relative "literal_type_analyzer"

module TypeGuessr
  module Core
    # AST analyzer for collecting variable definitions and method calls
    # Tracks local variables, parameters, and their method call patterns
    # Maintains scope awareness for accurate type inference
    class ASTAnalyzer < ::Prism::Visitor
      def initialize(file_path)
        super()
        @file_path = file_path
        @index = VariableIndex.instance
        @scopes = [{}] # Stack of scopes for local variables
        @instance_variables = [{}] # Stack of scopes for instance variables (class level)
        @class_variables = [{}] # Stack of scopes for class variables (class level)

        # Track current scope identifiers
        @class_stack = [] # Stack of class/module names for scope ID
        @method_stack = [] # Stack of method names for scope ID
      end

      # Track local variable assignments
      def visit_local_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column
        register_variable(var_name, line, column)

        # Analyze and store the type of the assigned value
        if node.value
          type = analyze_value_type(node.value)
          if type
            scope_type = determine_scope_type(var_name)
            scope_id = generate_scope_id(scope_type)
            @index.add_variable_type(
              file_path: @file_path,
              scope_type: scope_type,
              scope_id: scope_id,
              var_name: var_name,
              def_line: line,
              def_column: column,
              type: type
            )
          else
            store_call_assignment_if_applicable(var_name: var_name, def_line: line, def_column: column, value: node.value)
          end
        end

        super
      end

      # Track local variable targets (e.g., in multiple assignment)
      def visit_local_variable_target_node(node)
        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      # Track instance variable assignments
      def visit_instance_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column
        register_variable(var_name, line, column)

        # Analyze and store the type of the assigned value
        if node.value
          type = analyze_value_type(node.value)
          if type
            scope_type = determine_scope_type(var_name)
            scope_id = generate_scope_id(scope_type)
            @index.add_variable_type(
              file_path: @file_path,
              scope_type: scope_type,
              scope_id: scope_id,
              var_name: var_name,
              def_line: line,
              def_column: column,
              type: type
            )
          else
            store_call_assignment_if_applicable(var_name: var_name, def_line: line, def_column: column, value: node.value)
          end
        end

        super
      end

      # Track class variable assignments
      def visit_class_variable_write_node(node)
        var_name = node.name.to_s
        location = node.name_loc
        line = location.start_line
        column = location.start_column
        register_variable(var_name, line, column)

        # Analyze and store the type of the assigned value
        if node.value
          type = analyze_value_type(node.value)
          if type
            scope_type = determine_scope_type(var_name)
            scope_id = generate_scope_id(scope_type)
            @index.add_variable_type(
              file_path: @file_path,
              scope_type: scope_type,
              scope_id: scope_id,
              var_name: var_name,
              def_line: line,
              def_column: column,
              type: type
            )
          else
            store_call_assignment_if_applicable(var_name: var_name, def_line: line, def_column: column, value: node.value)
          end
        end

        super
      end

      # Track method parameters
      def visit_required_parameter_node(node)
        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_optional_parameter_node(node)
        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_rest_parameter_node(node)
        return super if !node.name

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
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_keyword_rest_parameter_node(node)
        return super if !node.name

        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      def visit_block_parameter_node(node)
        return super if !node.name

        var_name = node.name.to_s
        location = node.location
        register_variable(var_name, location.start_line, location.start_column)
        super
      end

      # Track method calls on variables
      def visit_call_node(node)
        return super if !node.receiver

        receiver = node.receiver

        # Extract variable name based on receiver type
        var_name = case receiver
                   when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
                     receiver.name.to_s
                   end

        if var_name
          method_name = node.name.to_s
          location = node.message_loc || node.location

          # Find the variable definition in current or parent scopes
          var_def = find_variable_in_scopes(var_name)
          if var_def
            scope_type = determine_scope_type(var_name)
            scope_id = generate_scope_id(scope_type)

            @index.add_method_call(
              file_path: @file_path,
              scope_type: scope_type,
              scope_id: scope_id,
              var_name: var_name,
              def_line: var_def[:line],
              def_column: var_def[:column],
              method_name: method_name,
              call_line: location.start_line,
              call_column: location.start_column
            )
          end
        end

        super
      end

      # Push new scope for method definitions
      def visit_def_node(node)
        method_name = node.name.to_s
        @method_stack.push(method_name)
        push_scope
        super
      ensure
        pop_scope
        @method_stack.pop
      end

      # Push new scope for blocks
      def visit_block_node(node)
        push_scope
        super
      ensure
        pop_scope
      end

      # Push new scope for class definitions
      def visit_class_node(node)
        class_name = extract_class_name(node.constant_path)
        @class_stack.push(class_name)
        push_scope
        push_member_scope
        super
      ensure
        pop_member_scope
        pop_scope
        @class_stack.pop
      end

      # Push new scope for module definitions
      def visit_module_node(node)
        module_name = extract_class_name(node.constant_path)
        @class_stack.push(module_name)
        push_scope
        push_member_scope
        super
      ensure
        pop_member_scope
        pop_scope
        @class_stack.pop
      end

      private

      # Analyze a value node and return its guessed type
      # @param node [Prism::Node] the value node to analyze
      # @return [Types::Type, nil] the guessed type or nil if cannot be determined
      def analyze_value_type(node)
        # Try literal type inference first
        type = LiteralTypeAnalyzer.infer(node)
        return type if type

        # Handle .new calls
        if node.is_a?(Prism::CallNode) && node.name == :new && node.receiver
          class_name = extract_class_name_from_receiver(node.receiver)
          return Types::ClassInstance.new(class_name) if class_name
        end

        nil
      end

      # Extract class name from a receiver node (for .new calls)
      # Resolves short names to fully qualified names using current nesting context
      # @param receiver [Prism::Node] the receiver node
      # @return [String, nil] the class name or nil
      def extract_class_name_from_receiver(receiver)
        case receiver
        when Prism::ConstantReadNode
          short_name = receiver.name.to_s
          resolve_constant_to_fqn(short_name)
        when Prism::ConstantPathNode
          receiver.slice
        end
      end

      # Resolve a short constant name to its fully qualified name using current nesting
      # Follows Ruby's constant lookup rules: searches from current nesting outward
      # @param short_name [String] the short constant name (e.g., "VariableTypeResolver")
      # @return [String] the fully qualified name (e.g., "RubyLsp::TypeGuessr::VariableTypeResolver")
      def resolve_constant_to_fqn(short_name)
        return short_name if @class_stack.empty?

        # Ruby's constant lookup searches from parent namespace, not current class
        # e.g., for nesting ["RubyLsp", "TypeGuessr", "Hover"] and short_name "Foo":
        # - Inside Hover class, referencing "Foo" looks for:
        #   1. RubyLsp::TypeGuessr::Foo (sibling in parent namespace)
        #   2. RubyLsp::Foo
        #   3. Foo (top-level)
        #
        # Since we don't have access to the index here, we return the most likely candidate:
        # the FQN using parent nesting (excluding current class)
        # This matches the common case where a class references a sibling in the same namespace
        parent_nesting = @class_stack[0...-1]
        return short_name if parent_nesting.empty?

        "#{parent_nesting.join("::")}::#{short_name}"
      end

      def register_variable(var_name, line, column)
        if var_name.start_with?("@@")
          @class_variables.last[var_name] = { line: line, column: column }
        elsif var_name.start_with?("@")
          @instance_variables.last[var_name] = { line: line, column: column }
        else
          @scopes.last[var_name] = { line: line, column: column }
        end
      end

      def find_variable_in_scopes(var_name)
        # Class variables: search class variable scopes
        if var_name.start_with?("@@")
          @class_variables.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        # Instance variables: search instance variable scopes
        elsif var_name.start_with?("@")
          @instance_variables.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        # Local variables: search local scopes
        else
          @scopes.reverse_each do |scope|
            return scope[var_name] if scope.key?(var_name)
          end
        end
        nil
      end

      def push_scope
        @scopes.push({})
      end

      def pop_scope
        @scopes.pop
      end

      def push_member_scope
        @instance_variables.push({})
        @class_variables.push({})
      end

      def pop_member_scope
        @instance_variables.pop
        @class_variables.pop
      end

      # Determine the scope type based on variable name
      def determine_scope_type(var_name)
        ScopeResolver.determine_scope_type(var_name)
      end

      # Generate scope ID for the current context
      # - For instance/class variables: "ClassName" or "Module::ClassName"
      # - For local variables: "ClassName#method_name"
      def generate_scope_id(scope_type)
        class_path = @class_stack.join("::")
        method_name = @method_stack.empty? ? nil : @method_stack.last

        ScopeResolver.generate_scope_id(
          scope_type,
          class_path: class_path,
          method_name: method_name
        )
      end

      # Extract class/module name from constant path node
      def extract_class_name(constant_path)
        case constant_path
        when Prism::ConstantReadNode
          constant_path.name.to_s
        when Prism::ConstantPathNode
          constant_path.slice
        else
          "Unknown"
        end
      end

      def store_call_assignment_if_applicable(var_name:, def_line:, def_column:, value:)
        return if !value.is_a?(Prism::CallNode)
        return if value.name == :new

        call_info = extract_call_chain_from_call_node(value)
        return if !call_info

        scope_type = determine_scope_type(var_name)
        scope_id = generate_scope_id(scope_type)

        @index.add_call_assignment(
          file_path: @file_path,
          scope_type: scope_type,
          scope_id: scope_id,
          var_name: var_name,
          def_line: def_line,
          def_column: def_column,
          receiver_var: call_info[:receiver_var],
          methods: call_info[:methods]
        )
      end

      # Extract receiver variable and method chain from a CallNode.
      # For `name.upcase.length`, returns: { receiver_var: "name", methods: ["upcase", "length"] }
      def extract_call_chain_from_call_node(call_node)
        methods = []
        current = call_node

        while current.is_a?(Prism::CallNode)
          methods << current.name.to_s
          current = current.receiver
        end

        receiver_var = case current
                       when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
                         current.name.to_s
                       end

        return nil if !receiver_var
        return nil if methods.empty?

        {
          receiver_var: receiver_var,
          methods: methods.reverse
        }
      end
    end
  end
end
