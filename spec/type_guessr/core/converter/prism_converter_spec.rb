# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "literal conversion" do
    it "converts integer literals" do
      source = "123"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.type.name).to eq("Integer")
    end

    it "converts string literals" do
      source = '"hello"'
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.type.name).to eq("String")
    end

    it "converts array literals" do
      source = "[]"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.type).to be_a(TypeGuessr::Core::Types::ArrayType)
    end

    it "converts hash literals" do
      source = "{}"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.type).to be_a(TypeGuessr::Core::Types::HashType)
    end
  end

  describe "array literal with internal dependencies" do
    it "tracks expressions inside array literals" do
      source = <<~RUBY
        class Foo
          def bar
            x = "hello"
            [x, 123]
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      def_node = class_node.methods.first
      array_node = def_node.return_node

      expect(array_node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(array_node.type).to be_a(TypeGuessr::Core::Types::ArrayType)
      expect(array_node.values).not_to be_nil
      expect(array_node.values.size).to eq(2)
      expect(array_node.values[0]).to be_a(TypeGuessr::Core::IR::LocalReadNode)
      expect(array_node.values[1]).to be_a(TypeGuessr::Core::IR::LiteralNode)
    end

    it "tracks method calls inside array literals" do
      source = <<~RUBY
        class Foo
          def bar
            x = "hello"
            [x.upcase, x.downcase]
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      def_node = class_node.methods.first
      array_node = def_node.return_node

      expect(array_node.values.size).to eq(2)
      expect(array_node.values[0]).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(array_node.values[0].method).to eq(:upcase)
      expect(array_node.values[1]).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(array_node.values[1].method).to eq(:downcase)
    end

    it "returns nil values for empty array" do
      source = "[]"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node.values).to be_nil
    end
  end

  describe "hash literal with internal dependencies" do
    it "tracks expressions inside hash literals" do
      source = <<~RUBY
        class Foo
          def bar
            x = "hello"
            { name: x, count: 123 }
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      def_node = class_node.methods.first
      hash_node = def_node.return_node

      expect(hash_node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(hash_node.type).to be_a(TypeGuessr::Core::Types::HashShape)
      expect(hash_node.values).not_to be_nil
      expect(hash_node.values.size).to eq(2)
      expect(hash_node.values[0]).to be_a(TypeGuessr::Core::IR::LocalReadNode)
      expect(hash_node.values[1]).to be_a(TypeGuessr::Core::IR::LiteralNode)
    end

    it "tracks instance variable reads inside hash literals" do
      source = <<~RUBY
        class Foo
          def bar
            @nodes = {}
            { nodes: @nodes, edges: @edges }
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      def_node = class_node.methods.first
      hash_node = def_node.return_node

      expect(hash_node.values.size).to eq(2)
      expect(hash_node.values[0]).to be_a(TypeGuessr::Core::IR::InstanceVariableReadNode)
      expect(hash_node.values[0].name).to eq(:@nodes)
      expect(hash_node.values[1]).to be_a(TypeGuessr::Core::IR::InstanceVariableReadNode)
      expect(hash_node.values[1].name).to eq(:@edges)
    end

    it "returns nil values for empty hash" do
      source = "{}"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node.values).to be_nil
    end
  end

  describe "nested literals" do
    it "handles nested array in hash" do
      source = "{ items: [1, 2, 3] }"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.values.size).to eq(1)

      inner_array = node.values.first
      expect(inner_array).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(inner_array.type).to be_a(TypeGuessr::Core::Types::ArrayType)
      expect(inner_array.values.size).to eq(3)
    end

    it "handles nested hash in array" do
      source = "[{ a: 1 }, { b: 2 }]"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.values.size).to eq(2)

      expect(node.values[0]).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.values[0].type).to be_a(TypeGuessr::Core::Types::HashShape)
      expect(node.values[1]).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.values[1].type).to be_a(TypeGuessr::Core::Types::HashShape)
    end
  end

  describe "variable assignment" do
    it "converts local variable assignment" do
      source = 'x = "hello"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
      expect(node.name).to eq(:x)
      expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.value.type.name).to eq("String")
    end

    it "converts instance variable assignment" do
      source = '@name = "John"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
      expect(node.name).to eq(:@name)
    end

    it "converts class variable assignment" do
      source = "@@count = 0"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::ClassVariableWriteNode)
      expect(node.name).to eq(:@@count)
    end
  end

  describe "variable read" do
    it "looks up variable from context" do
      source = <<~RUBY
        x = "hello"
        x
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert assignment
      assignment = parsed.value.statements.body[0]
      write_node = converter.convert(assignment, context)

      # Convert read
      read = parsed.value.statements.body[1]
      read_node = converter.convert(read, context)

      # Read creates a LocalReadNode pointing to the LocalWriteNode
      expect(read_node).to be_a(TypeGuessr::Core::IR::LocalReadNode)
      expect(read_node.write_node).to eq(write_node)
      # Should share called_methods array for duck typing
      expect(read_node.called_methods).to be(write_node.called_methods)
    end
  end

  describe "instance variable called_methods sharing" do
    it "shares called_methods with parameter when assigned from parameter" do
      source = <<~RUBY
        class Foo
          def initialize(adapter)
            @adapter = adapter
          end

          def process
            @adapter.call_method
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      # Get the initialize method's parameter
      init_method = class_node.methods.find { |m| m.name == :initialize }
      param_node = init_method.params.first

      # The InstanceVariableWriteNode should share called_methods with the ParamNode
      # When @adapter.call_method is called, :call_method should be in param's called_methods
      expect(param_node.called_methods).to include(:call_method)
    end
  end

  describe "class variable called_methods sharing" do
    it "shares called_methods with parameter when assigned from parameter" do
      source = <<~RUBY
        class Foo
          def setup(adapter)
            @@adapter = adapter
            @@adapter.call_method
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      # Get the setup method's parameter
      setup_method = class_node.methods.find { |m| m.name == :setup }
      param_node = setup_method.params.first

      # The ClassVariableWriteNode should share called_methods with the ParamNode
      expect(param_node.called_methods).to include(:call_method)
    end
  end

  describe "method call conversion" do
    it "converts simple method call" do
      source = "foo"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:foo)
      expect(node.receiver).to be_nil
    end

    it "converts method call with receiver" do
      source = <<~RUBY
        user = nil
        user.profile
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert assignment first
      converter.convert(parsed.value.statements.body[0], context)

      # Now convert the call
      node = converter.convert(parsed.value.statements.body[1], context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:profile)
      expect(node.receiver).to be_a(TypeGuessr::Core::IR::LocalReadNode)
    end

    it "tracks method calls for duck typing" do
      source = <<~RUBY
        user = nil
        user.profile
        user.name
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert all statements
      parsed.value.statements.body.each do |stmt|
        converter.convert(stmt, context)
      end

      # Check that user variable has called_methods tracked
      user_var = context.lookup_variable(:user)
      expect(user_var.called_methods).to contain_exactly(:profile, :name)
    end

    it "converts method call with arguments" do
      source = "foo(1, 2)"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:foo)
      expect(node.args.size).to eq(2)
    end
  end

  describe "block conversion" do
    it "creates block parameter slots" do
      source = "[1, 2, 3].each { |x| x }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:each)
      expect(node.block_params.size).to eq(1)
      expect(node.block_params.first).to be_a(TypeGuessr::Core::IR::BlockParamSlot)
      expect(node.block_params.first.index).to eq(0)
    end

    it "registers block parameters in context" do
      source = "[1, 2, 3].map { |x| x * 2 }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Block parameter should not be visible in outer context
      expect(context.lookup_variable(:x)).to be_nil
    end
  end

  describe "if statement conversion" do
    it "creates merge node for if/else" do
      source = <<~RUBY
        if condition
          x = "hello"
        else
          x = 123
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(node.branches.size).to eq(2)
    end

    it "creates merge node for inline if (modifier if)" do
      source = "x = 1 if condition"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Variable should be a MergeNode with WriteNode and nil
      var = context.lookup_variable(:x)
      expect(var).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(var.branches.size).to eq(2)

      # One branch is LocalWriteNode, one is LiteralNode(nil)
      types = var.branches.map(&:class).map(&:name)
      expect(types).to include("TypeGuessr::Core::IR::LocalWriteNode")
      expect(types).to include("TypeGuessr::Core::IR::LiteralNode")
    end

    it "creates merge node for inline unless (modifier unless)" do
      source = "x = 1 unless condition"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Variable should be a MergeNode with WriteNode and nil
      var = context.lookup_variable(:x)
      expect(var).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(var.branches.size).to eq(2)
    end
  end

  describe "method definition conversion" do
    it "converts method with parameters" do
      source = <<~RUBY
        def foo(x, y = 10)
          x + y
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
      expect(node.name).to eq(:foo)
      expect(node.params.size).to eq(2)
      expect(node.params[0]).to be_a(TypeGuessr::Core::IR::ParamNode)
      expect(node.params[0].name).to eq(:x)
      expect(node.params[0].default_value).to be_nil
      expect(node.params[1].name).to eq(:y)
      expect(node.params[1].default_value).to be_a(TypeGuessr::Core::IR::LiteralNode)
    end

    it "tracks method calls on parameters for duck typing" do
      source = <<~RUBY
        def process(recipe)
          recipe.comments
          recipe.title
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
      param = node.params.first
      expect(param.called_methods).to contain_exactly(:comments, :title)
    end

    describe "destructuring parameters" do
      it "converts simple destructuring (a, b)" do
        source = <<~RUBY
          def foo((a, b))
            a + b
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        expect(node.params.size).to eq(2)
        expect(node.params.map(&:name)).to contain_exactly(:a, :b)
      end

      it "converts destructuring with regular params" do
        source = <<~RUBY
          def foo((a, b), c)
            a + b + c
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        expect(node.params.size).to eq(3)
        expect(node.params.map(&:name)).to eq(%i[a b c])
      end

      it "registers destructured params in context for body reference" do
        source = <<~RUBY
          def foo((a, b))
            a
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        # The return_node should reference the param 'a' from destructuring
        expect(node.return_node).to be_a(TypeGuessr::Core::IR::LocalReadNode)
        expect(node.return_node.name).to eq(:a)
        # Should have a write_node since it was registered from destructuring
        expect(node.return_node.write_node).to be_a(TypeGuessr::Core::IR::ParamNode)
      end

      it "handles nested destructuring" do
        source = <<~RUBY
          def foo(((a, b), c))
            a + b + c
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        # Nested destructuring should extract all inner params
        expect(node.params.map(&:name)).to contain_exactly(:a, :b, :c)
      end
    end
  end

  describe "method with rescue/ensure" do
    it "converts method with rescue block" do
      source = <<~RUBY
        def load_config
          config = read_file
          config
        rescue => e
          default_config
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
      expect(node.name).to eq(:load_config)
      # Should have body nodes from main body and rescue clause
      expect(node.body_nodes.size).to be >= 2
    end

    it "extracts body nodes from method with ensure" do
      source = <<~RUBY
        def process
          result = compute
          result
        ensure
          cleanup
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
      expect(node.body_nodes.size).to be >= 2
    end

    it "handles begin/rescue/else/ensure" do
      source = <<~RUBY
        def full_example
          x = 1
        rescue
          x = 2
        else
          x = 3
        ensure
          cleanup
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
      # Should have nodes from: main body (1), rescue (1), else (1), ensure (1)
      expect(node.body_nodes.size).to eq(4)
    end
  end

  describe "constant conversion" do
    it "converts constant read" do
      source = "DEFAULT_NAME"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::ConstantNode)
      expect(node.name).to eq("DEFAULT_NAME")
      expect(node.dependency).to be_nil
    end

    it "converts constant assignment" do
      source = 'DEFAULT_NAME = "John"'
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::ConstantNode)
      expect(node.name).to eq("DEFAULT_NAME")
      expect(node.dependency).to be_a(TypeGuessr::Core::IR::LiteralNode)
    end
  end

  describe "location conversion" do
    it "converts Prism location to IR Loc" do
      source = '"hello"'
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node.loc).to be_a(TypeGuessr::Core::IR::Loc)
      expect(node.loc.line).to eq(1)
      expect(node.loc.col_range).to be_a(Range)
    end
  end

  describe "compound assignments" do
    describe "local variable ||= (or-assign)" do
      it "creates LocalWriteNode with value for undefined variable" do
        source = "x ||= 1"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        # For undefined variable, value is just the RHS
        expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end

      it "creates MergeNode for defined variable" do
        source = <<~RUBY
          x = nil
          x ||= 1
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        # Convert first assignment
        converter.convert(parsed.value.statements.body[0], context)

        # Convert ||=
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        # Should be MergeNode with original and new value
        expect(node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.value.branches.size).to eq(2)
      end
    end

    describe "local variable &&= (and-assign)" do
      it "creates LocalWriteNode with value for undefined variable" do
        source = 'x &&= "string"'
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
      end

      it "creates MergeNode for defined variable" do
        source = <<~RUBY
          x = "hello"
          x &&= "world"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.value.branches.size).to eq(2)
      end
    end

    describe "local variable operator writes (+=, -=, *=, /=)" do
      it "creates CallNode for +=" do
        source = <<~RUBY
          x = 1
          x += 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:+)
        expect(node.value.args.size).to eq(1)
      end

      it "creates CallNode for -=" do
        source = <<~RUBY
          count = 10
          count -= 1
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:-)
      end

      it "creates CallNode for *=" do
        source = <<~RUBY
          x = 5
          x *= 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:*)
      end

      it "creates CallNode for /=" do
        source = <<~RUBY
          x = 10
          x /= 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:/)
      end
    end

    describe "instance variable ||=" do
      it "creates InstanceVariableWriteNode with MergeNode for defined variable" do
        source = <<~RUBY
          class Foo
            def setup
              @cache = nil
              @cache ||= {}
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        setup_method = class_node.methods.first
        # The body should contain both assignments
        body_nodes = setup_method.body_nodes

        # Second node should be the ||= assignment
        or_write_node = body_nodes[1]
        expect(or_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(or_write_node.name).to eq(:@cache)
        expect(or_write_node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "instance variable &&=" do
      it "creates InstanceVariableWriteNode with MergeNode" do
        source = <<~RUBY
          class Foo
            def process
              @value = "initial"
              @value &&= "updated"
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        process_method = class_node.methods.first
        and_write_node = process_method.body_nodes[1]

        expect(and_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(and_write_node.name).to eq(:@value)
        expect(and_write_node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "instance variable operator writes" do
      it "creates InstanceVariableWriteNode with CallNode for +=" do
        source = <<~RUBY
          class Foo
            def increment
              @count = 0
              @count += 1
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        increment_method = class_node.methods.first
        op_write_node = increment_method.body_nodes[1]

        expect(op_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(op_write_node.name).to eq(:@count)
        expect(op_write_node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(op_write_node.value.method).to eq(:+)
      end
    end
  end

  describe "case statements" do
    describe "case/when" do
      it "creates MergeNode for case with multiple when clauses" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then "two"
          else "other"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(3)
        node.branches.each do |branch|
          expect(branch).to be_a(TypeGuessr::Core::IR::LiteralNode)
          expect(branch.type.name).to eq("String")
        end
      end

      it "returns single branch when only one when clause" do
        source = <<~RUBY
          case n
          when 1 then "one"
          else "default"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(2)
      end
    end

    describe "case without else" do
      it "includes nil as possible branch" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then "two"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # 2 when clauses + nil for missing else
        expect(node.branches.size).to eq(3)

        # One of the branches should be nil
        nil_branch = node.branches.find { |b| b.type.name == "NilClass" }
        expect(nil_branch).not_to be_nil
      end
    end

    describe "case with variable assignments" do
      it "creates MergeNode for variables assigned in branches" do
        source = <<~RUBY
          case n
          when 1 then x = "a"
          when 2 then x = "b"
          else x = "c"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        # Variable x should be a MergeNode
        x_var = context.lookup_variable(:x)
        expect(x_var).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(x_var.branches.size).to eq(3)
      end
    end

    describe "case without predicate" do
      it "converts case without predicate (like if/elsif chain)" do
        source = <<~RUBY
          case
          when flag then 1
          when other then 2
          else 3
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(3)
        node.branches.each do |branch|
          expect(branch).to be_a(TypeGuessr::Core::IR::LiteralNode)
          expect(branch.type.name).to eq("Integer")
        end
      end
    end

    describe "case with empty when clause" do
      it "treats empty when clause as nil" do
        source = <<~RUBY
          case n
          when 1 then
          when 2 then "two"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # Should have 3 branches: nil (empty when), String, nil (no else)
        nil_branches = node.branches.select { |b| b.type.name == "NilClass" }
        expect(nil_branches.size).to be >= 1
      end
    end

    describe "case with non-returning branches" do
      it "excludes raise from branch types" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then raise "error"
          else "other"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # raise branch should be excluded
        expect(node.branches.size).to eq(2)
        node.branches.each do |branch|
          expect(branch.type.name).to eq("String")
        end
      end
    end
  end

  describe "container mutation tracking" do
    describe "hash mutations" do
      it "adds field to HashShape on symbol key assignment" do
        source = <<~RUBY
          h = {}
          h[:key] = "value"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        h_var = context.lookup_variable(:h)
        expect(h_var.value.type).to be_a(TypeGuessr::Core::Types::HashShape)
        expect(h_var.value.type.fields[:key].name).to eq("String")
      end

      it "widens HashShape to HashType on non-symbol key" do
        source = <<~RUBY
          h = { a: 1 }
          h["string"] = 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        h_var = context.lookup_variable(:h)
        expect(h_var.value.type).to be_a(TypeGuessr::Core::Types::HashType)
      end
    end

    describe "array mutations" do
      it "updates ArrayType element type on indexed assignment" do
        source = <<~RUBY
          arr = []
          arr[0] = "string"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(arr_var.value.type.element_type.name).to eq("String")
      end

      it "creates union element types with << operator" do
        source = <<~RUBY
          arr = [1]
          arr << "string"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(arr_var.value.type.element_type).to be_a(TypeGuessr::Core::Types::Union)
      end
    end
  end

  describe "return statement handling" do
    describe "explicit return" do
      it "creates ReturnNode for return with value" do
        source = <<~RUBY
          def foo
            return 1
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::DefNode)
        # return_node should be the explicit return
        expect(node.return_node).to be_a(TypeGuessr::Core::IR::ReturnNode)
        expect(node.return_node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.return_node.value.type.name).to eq("Integer")
      end
    end

    describe "return without value" do
      it "creates ReturnNode with nil literal" do
        source = <<~RUBY
          def foo
            return
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node.return_node).to be_a(TypeGuessr::Core::IR::ReturnNode)
        expect(node.return_node.value.type.name).to eq("NilClass")
      end
    end

    describe "multiple return points" do
      it "creates MergeNode for methods with multiple returns" do
        source = <<~RUBY
          def foo(flag)
            return "early" if flag
            "normal"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # Should have: explicit return "early" + implicit return "normal"
        expect(node.return_node.branches.size).to eq(2)
      end

      it "handles return in case statement" do
        source = <<~RUBY
          def foo(n)
            case n
            when 1 then return "one"
            when 2 then return "two"
            end
            "default"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        # Should have returns from case + implicit "default"
        expect(node.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.return_node.branches.size).to be >= 2
      end
    end

    describe "implicit return" do
      it "uses last expression as return when no explicit return" do
        source = <<~RUBY
          def foo
            x = 1
            x + 1
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node.return_node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.return_node.method).to eq(:+)
      end
    end
  end

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

  describe "standalone begin/rescue/ensure" do
    it "converts standalone begin/rescue block" do
      source = <<~RUBY
        begin
          risky_operation
        rescue => e
          fallback
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      # Should return the last node from the begin block
      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
    end

    it "converts begin/rescue/else/ensure" do
      source = <<~RUBY
        begin
          main_operation
        rescue
          handle_error
        else
          on_success
        ensure
          cleanup
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      # Should return the last node (from ensure clause)
      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
    end
  end

  describe "splat operations" do
    describe "splat in arrays" do
      it "creates CallNode for to_a on splatted expression" do
        source = <<~RUBY
          arr = [1, 2, 3]
          [*arr, 4]
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        # First element should be CallNode for to_a
        expect(node.values.first).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.values.first.method).to eq(:to_a)
      end
    end

    describe "double splat in hashes" do
      it "tracks double splat in hash literals" do
        source = <<~RUBY
          h = { a: 1 }
          { **h, b: 2 }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
        # Double splat causes type inference to widen to HashType
        expect(node.type).to be_a(TypeGuessr::Core::Types::HashType)
        # Should have values including the splatted hash reference
        expect(node.values).not_to be_nil
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

        singleton = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::ClassModuleNode) && m.name.start_with?("<Class:") }
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

    describe "OrNode (|| operator)" do
      it "converts || to MergeNode with both branches" do
        source = "a || b"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(2)
      end

      it "converts method with || chain to have proper return_node" do
        source = <<~RUBY
          class Foo
            def lookup(name)
              @cache[name] || @fallback[name]
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        lookup_method = class_node.methods.first
        expect(lookup_method.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
      end

      it "converts predicate method with || chain" do
        source = <<~RUBY
          class Foo
            def valid?(node)
              node.is_a?(String) || node.is_a?(Symbol)
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        valid_method = class_node.methods.first
        expect(valid_method.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "AndNode (&& operator)" do
      it "converts && to MergeNode with both branches" do
        source = "a && b"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(2)
      end

      it "converts method with && chain to have proper return_node" do
        source = <<~RUBY
          class Foo
            def eql?(other)
              self.class == other.class && @value == other.value
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

    describe "MultiWriteNode (multiple assignment)" do
      it "converts multiple assignment and registers variables" do
        source = "a, b = [1, 2]"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        expect(context.lookup_variable(:a)).not_to be_nil
        expect(context.lookup_variable(:b)).not_to be_nil
      end

      it "converts multiple assignment with splat" do
        source = "first, *rest = array"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        expect(context.lookup_variable(:first)).not_to be_nil
        expect(context.lookup_variable(:rest)).not_to be_nil
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

    describe "ParenthesesNode" do
      it "unwraps parenthesized expression" do
        source = "(1 + 2)"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.method).to eq(:+)
      end

      it "properly handles assignment from parenthesized expression" do
        source = "x = (a || b)"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
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
