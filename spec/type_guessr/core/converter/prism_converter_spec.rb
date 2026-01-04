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

  describe "variable assignment" do
    it "converts local variable assignment" do
      source = 'x = "hello"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::VariableNode)
      expect(node.name).to eq(:x)
      expect(node.kind).to eq(:local)
      expect(node.dependency).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.dependency.type.name).to eq("String")
    end

    it "converts instance variable assignment" do
      source = '@name = "John"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::VariableNode)
      expect(node.name).to eq(:@name)
      expect(node.kind).to eq(:instance)
    end

    it "converts class variable assignment" do
      source = "@@count = 0"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::VariableNode)
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
      var_node = converter.convert(assignment, context)

      # Convert read
      read = parsed.value.statements.body[1]
      read_node = converter.convert(read, context)

      # Read creates a new node but points to the assignment via dependency
      expect(read_node).to be_a(TypeGuessr::Core::IR::VariableNode)
      expect(read_node.dependency).to eq(var_node)
      # Should share called_methods array for duck typing
      expect(read_node.called_methods).to be(var_node.called_methods)
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
      expect(node.receiver).to be_a(TypeGuessr::Core::IR::VariableNode)
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
        expect(node.return_node).to be_a(TypeGuessr::Core::IR::VariableNode)
        expect(node.return_node.name).to eq(:a)
        # Should have a dependency since it was registered from destructuring
        expect(node.return_node.dependency).to be_a(TypeGuessr::Core::IR::ParamNode)
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
