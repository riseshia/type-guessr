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
      expect(array_node.values[0]).to be_a(TypeGuessr::Core::IR::ReadNode)
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
      expect(hash_node.values[0]).to be_a(TypeGuessr::Core::IR::ReadNode)
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
      expect(hash_node.values[0]).to be_a(TypeGuessr::Core::IR::ReadNode)
      expect(hash_node.values[0].name).to eq(:@nodes)
      expect(hash_node.values[1]).to be_a(TypeGuessr::Core::IR::ReadNode)
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

      expect(node).to be_a(TypeGuessr::Core::IR::WriteNode)
      expect(node.name).to eq(:x)
      expect(node.kind).to eq(:local)
      expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.value.type.name).to eq("String")
    end

    it "converts instance variable assignment" do
      source = '@name = "John"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::WriteNode)
      expect(node.name).to eq(:@name)
      expect(node.kind).to eq(:instance)
    end

    it "converts class variable assignment" do
      source = "@@count = 0"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::WriteNode)
      expect(node.name).to eq(:@@count)
      expect(node.kind).to eq(:class)
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

      # Read creates a ReadNode pointing to the WriteNode
      expect(read_node).to be_a(TypeGuessr::Core::IR::ReadNode)
      expect(read_node.write_node).to eq(write_node)
      # Should share called_methods array for duck typing
      expect(read_node.called_methods).to be(write_node.called_methods)
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
      expect(node.receiver).to be_a(TypeGuessr::Core::IR::ReadNode)
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

      # One branch is WriteNode, one is LiteralNode(nil)
      types = var.branches.map(&:class).map(&:name)
      expect(types).to include("TypeGuessr::Core::IR::WriteNode")
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
        expect(node.return_node).to be_a(TypeGuessr::Core::IR::ReadNode)
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
end
