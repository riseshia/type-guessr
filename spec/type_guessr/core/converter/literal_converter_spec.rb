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
      expect(node.type).to be_a(TypeGuessr::Core::Types::TupleType)
      expect(node.type.element_types).to eq([])
    end

    it "converts hash literals" do
      source = "{}"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.type).to be_a(TypeGuessr::Core::Types::HashShape)
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
      expect(inner_array.type).to be_a(TypeGuessr::Core::Types::TupleType)
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
end
