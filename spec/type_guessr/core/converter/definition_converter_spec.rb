# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

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
      expect(param.called_methods.map(&:name)).to contain_exactly(:comments, :title)
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
end
