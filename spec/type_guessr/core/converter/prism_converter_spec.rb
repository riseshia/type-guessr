# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "self reference" do
    describe "explicit self" do
      it "creates SelfNode for self keyword" do
        source = <<~RUBY
          class Foo
            def bar
              self
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        bar_method = class_node.methods.first
        expect(bar_method.return_node).to be_a(TypeGuessr::Core::IR::SelfNode)
        expect(bar_method.return_node.class_name).to eq("Foo")
        expect(bar_method.return_node.singleton).to be false
      end
    end

    describe "self in singleton method" do
      it "creates SelfNode with singleton: true" do
        source = <<~RUBY
          class Foo
            def self.bar
              self
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        bar_method = class_node.methods.first
        expect(bar_method.return_node).to be_a(TypeGuessr::Core::IR::SelfNode)
        expect(bar_method.return_node.singleton).to be true
      end
    end

    describe "implicit self as receiver" do
      it "creates SelfNode for method calls without explicit receiver" do
        source = <<~RUBY
          class Foo
            def bar
              baz
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        bar_method = class_node.methods.first
        call_node = bar_method.return_node

        expect(call_node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(call_node.receiver).to be_a(TypeGuessr::Core::IR::SelfNode)
        expect(call_node.receiver.class_name).to eq("Foo")
      end
    end
  end

  describe "complex edge cases" do
    describe "nested compound assignments" do
      it "handles chained ||= assignments" do
        source = <<~RUBY
          class Foo
            def data
              @cache ||= @backup ||= {}
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        data_method = class_node.methods.first
        # The return node should exist (chained ||= is valid)
        expect(data_method.return_node).not_to be_nil
      end

      it "handles ||= with method call value" do
        source = <<~RUBY
          class Foo
            def fetch
              @data ||= load_data
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        fetch_method = class_node.methods.first
        # Return node should be the ||= result
        expect(fetch_method.return_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
      end
    end

    describe "compound assignment in control flow" do
      it "handles ||= inside case branch" do
        source = <<~RUBY
          case type
          when :a then x ||= "default_a"
          when :b then x ||= "default_b"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # Variable x should be registered
        x_var = context.lookup_variable(:x)
        expect(x_var).not_to be_nil
      end

      it "handles += inside if branches" do
        source = <<~RUBY
          x = 0
          if condition
            x += 1
          else
            x += 2
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        x_var = context.lookup_variable(:x)
        expect(x_var).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(x_var.branches.size).to eq(2)
      end
    end

    describe "deeply nested control flow" do
      it "handles nested if statements with variable assignments" do
        source = <<~RUBY
          if a
            if b
              x = 1
            else
              x = 2
            end
          else
            x = 3
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        x_var = context.lookup_variable(:x)
        expect(x_var).to be_a(TypeGuessr::Core::IR::MergeNode)
        # Should merge outer branches (inner if merged + else)
        expect(x_var.branches.size).to eq(2)
      end

      it "handles case inside if" do
        source = <<~RUBY
          if flag
            case n
            when 1 then result = "one"
            when 2 then result = "two"
            end
          else
            result = "none"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        result_var = context.lookup_variable(:result)
        expect(result_var).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "chained method calls with blocks" do
      it "handles map followed by select" do
        source = <<~RUBY
          [1, 2, 3].map { |x| x * 2 }.select { |y| y > 2 }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.method).to eq(:select)
        expect(node.receiver).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.receiver.method).to eq(:map)
      end

      it "handles nested blocks" do
        source = <<~RUBY
          [[1, 2], [3, 4]].map { |arr| arr.map { |x| x * 2 } }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.method).to eq(:map)
        expect(node.block_body).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.block_body.method).to eq(:map)
      end
    end

    describe "rescue with exception binding" do
      it "converts rescue with exception variable" do
        source = <<~RUBY
          def risky
            dangerous_operation
          rescue StandardError => e
            handle_error(e)
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        expect(node.body_nodes.size).to be >= 2
      end

      it "converts multiple rescue clauses" do
        source = <<~RUBY
          def multi_rescue
            operation
          rescue TypeError => e
            handle_type_error(e)
          rescue ArgumentError => e
            handle_arg_error(e)
          rescue => e
            handle_generic(e)
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        # Should have body nodes from main body + all rescue clauses
        expect(node.body_nodes.size).to be >= 4
      end

      it "registers exception variable in context and tracks method calls" do
        source = <<~RUBY
          begin
            risky
          rescue StandardError => e
            e.message
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        # Exception variable should be registered
        write_node = context.lookup_variable(:e)
        expect(write_node).not_to be_nil
        expect(write_node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        # Method calls on exception variable should be tracked
        expect(write_node.called_methods.map(&:name)).to include(:message)
      end

      it "infers exception type from rescue clause" do
        source = <<~RUBY
          begin
            risky
          rescue TypeError => e
            e
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        write_node = context.lookup_variable(:e)
        expect(write_node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(write_node.value.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(write_node.value.type.name).to eq("TypeError")
      end

      it "uses StandardError as default when no exception class specified" do
        source = <<~RUBY
          begin
            risky
          rescue => e
            e
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        write_node = context.lookup_variable(:e)
        expect(write_node.value.type.name).to eq("StandardError")
      end

      it "handles dynamic constant path in rescue clause" do
        source = <<~RUBY
          begin
            risky
          rescue self::CustomError => e
            e
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        expect { converter.convert(parsed.value.statements.body.first, context) }.not_to raise_error
      end
    end

    describe "pattern matching (case/in)" do
      it "converts simple pattern matching" do
        source = <<~RUBY
          case data
          in { name: n }
            n
          in [first, *rest]
            first
          else
            "unknown"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        # Pattern matching is converted similarly to case/when
        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "multiple assignment (destructuring)" do
      it "converts simple multiple assignment" do
        source = "a, b = [1, 2]"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        # Multiple assignment may not create nodes for individual variables
        # depending on implementation - just ensure no crash
        expect { converter.convert(parsed.value.statements.body.first, context) }.not_to raise_error
      end

      it "converts splat in multiple assignment" do
        source = "first, *rest = [1, 2, 3, 4]"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        expect { converter.convert(parsed.value.statements.body.first, context) }.not_to raise_error
      end
    end

    describe "complex return scenarios" do
      it "handles return inside rescue" do
        source = <<~RUBY
          def safe_load
            return load_data
          rescue
            return default_data
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        # Should have return nodes from both main body and rescue
        expect(node.return_node).not_to be_nil
      end

      it "handles return with complex expression" do
        source = <<~RUBY
          def compute
            return items.map { |i| i * 2 }.sum
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node.return_node).to be_a(TypeGuessr::Core::IR::ReturnNode)
        expect(node.return_node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.return_node.value.method).to eq(:sum)
      end
    end

    describe "class and module nesting" do
      it "handles deeply nested classes" do
        source = <<~RUBY
          class Outer
            class Middle
              class Inner
                def foo
                  "inner"
                end
              end
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::ClassModuleNode)
        expect(node.name).to eq("Outer")

        # Find nested class
        middle = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::ClassModuleNode) }
        expect(middle).not_to be_nil
        expect(middle.name).to eq("Middle")
      end

      it "handles module with class inside" do
        source = <<~RUBY
          module MyModule
            class MyClass
              def bar
                42
              end
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::ClassModuleNode)
        nested_class = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::ClassModuleNode) }
        expect(nested_class).not_to be_nil
        expect(nested_class.name).to eq("MyClass")
      end
    end

    describe "singleton class" do
      it "handles singleton class with methods" do
        source = <<~RUBY
          class Foo
            class << self
              def bar
                "class method"
              end

              def baz
                "another class method"
              end
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        singleton = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::ClassModuleNode) && m.name.include?("<Class:") }
        expect(singleton).not_to be_nil
        expect(singleton.methods.size).to eq(2)
      end
    end

    describe "complex hash and array operations" do
      it "handles nested hash mutation" do
        source = <<~RUBY
          h = { outer: {} }
          h[:outer][:inner] = "value"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        # Should be a call node for []=
        expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.method).to eq(:[]=)
      end

      it "handles array with mixed literal and variable elements" do
        source = <<~RUBY
          x = "hello"
          y = 42
          [x, y, true, nil, :symbol]
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)
        node = converter.convert(parsed.value.statements.body[2], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.values.size).to eq(5)
        expect(node.values[0]).to be_a(TypeGuessr::Core::IR::LocalReadNode)
        expect(node.values[1]).to be_a(TypeGuessr::Core::IR::LocalReadNode)
        expect(node.values[2]).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end
    end

    describe "method parameters edge cases" do
      it "handles all parameter types in one method" do
        source = <<~RUBY
          def complex(a, b = 1, *args, c:, d: 2, **kwargs, &block)
            [a, b, args, c, d, kwargs, block]
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        param_kinds = node.params.map(&:kind)

        expect(param_kinds).to include(:required)
        expect(param_kinds).to include(:optional)
        expect(param_kinds).to include(:rest)
        expect(param_kinds).to include(:keyword_required)
        expect(param_kinds).to include(:keyword_optional)
        expect(param_kinds).to include(:keyword_rest)
        expect(param_kinds).to include(:block)
      end

      it "handles forwarding parameter (...)" do
        source = <<~RUBY
          def forward(...)
            other_method(...)
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        forwarding_param = node.params.find { |p| p.kind == :forwarding }
        expect(forwarding_param).not_to be_nil
      end
    end

    describe "edge cases in literals" do
      it "handles heredoc strings" do
        source = <<~RUBY
          <<~TEXT
            This is a
            multiline string
          TEXT
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type.name).to eq("String")
      end

      it "handles complex regex" do
        source = '/^(?<name>\w+)@(?<domain>\w+\.\w+)$/'
        parsed = Prism.parse(source)
        node = converter.convert(parsed.value.statements.body.first)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type.name).to eq("Regexp")
      end

      it "handles endless range" do
        source = "1.."
        parsed = Prism.parse(source)
        node = converter.convert(parsed.value.statements.body.first)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type).to be_a(TypeGuessr::Core::Types::RangeType)
      end

      it "handles beginless range" do
        source = "..10"
        parsed = Prism.parse(source)
        node = converter.convert(parsed.value.statements.body.first)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type).to be_a(TypeGuessr::Core::Types::RangeType)
      end
    end
  end

  describe "unhandled node types" do
    before { pending "Not yet implemented - these node types need PrismConverter support" }

    describe "SuperNode and ForwardingSuperNode" do
      it "converts super with arguments to CallNode" do
        source = <<~RUBY
          class Child < Parent
            def initialize(name)
              super(name)
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        init_method = class_node.methods.first
        expect(init_method.body_nodes).not_to be_empty
        # super is treated as a special method call
        expect(init_method.body_nodes.first).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(init_method.body_nodes.first.method).to eq(:super)
      end

      it "converts super without arguments to CallNode" do
        source = <<~RUBY
          class Child < Parent
            def process
              super
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        process_method = class_node.methods.first
        expect(process_method.body_nodes).not_to be_empty
        expect(process_method.return_node).to be_a(TypeGuessr::Core::IR::CallNode)
      end

      it "converts super && expression properly" do
        source = <<~RUBY
          class Child < Parent
            def eql?(other)
              super && @extra == other.extra
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        eql_method = class_node.methods.first
        expect(eql_method.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "WhileNode and UntilNode" do
      it "converts while loop (returns nil type)" do
        source = <<~RUBY
          while condition
            do_something
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        # While loops return nil, should create LiteralNode with NilClass
        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type.name).to eq("NilClass")
      end

      it "converts until loop" do
        source = <<~RUBY
          until done
            process
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end

      it "converts modifier while" do
        source = "do_something while condition"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).not_to be_nil
      end
    end

    describe "LambdaNode" do
      it "converts lambda literal to LiteralNode with Proc type" do
        source = "-> { 42 }"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type.name).to eq("Proc")
      end

      it "converts lambda with parameters" do
        source = "->(x, y) { x + y }"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type.name).to eq("Proc")
      end

      it "tracks lambda assigned to variable with Proc type" do
        source = <<~RUBY
          processor = ->(x) { x * 2 }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.value.type.name).to eq("Proc")
      end
    end

    describe "ForNode" do
      it "converts for loop (registers loop variable)" do
        source = <<~RUBY
          for i in 1..10
            puts i
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        # for loop should register variable i
        expect(context.lookup_variable(:i)).not_to be_nil
      end
    end

    describe "YieldNode" do
      it "converts yield statements" do
        source = <<~RUBY
          def each
            yield 1
            yield 2
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        def_node = converter.convert(parsed.value.statements.body.first, context)

        expect(def_node).to be_a(TypeGuessr::Core::IR::DefNode)
        expect(def_node.body_nodes).not_to be_empty
      end
    end

    describe "DefinedNode" do
      it "converts defined? to LiteralNode with optional String type" do
        source = "defined?(some_var)"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        # defined? returns String or nil
        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end
    end

    describe "AliasMethodNode" do
      it "registers aliased method" do
        source = <<~RUBY
          class Foo
            def original; end
            alias copy original
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        # Both original and copy should be registered
        expect(class_node.methods.size).to eq(2)
        method_names = class_node.methods.map(&:name)
        expect(method_names).to include(:original)
        expect(method_names).to include(:copy)
      end
    end

    describe "GlobalVariableWriteNode and GlobalVariableReadNode" do
      it "converts global variable write" do
        source = "$global = 42"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).not_to be_nil
      end

      it "converts global variable read" do
        source = "$global"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).not_to be_nil
      end
    end
  end
end
