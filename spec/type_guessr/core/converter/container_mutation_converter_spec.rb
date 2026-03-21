# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

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
      it "updates to TupleType on indexed assignment to empty array" do
        source = <<~RUBY
          arr = []
          arr[0] = "string"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::TupleType)
        expect(arr_var.value.type.element_types.map(&:to_s)).to eq(["String"])
      end

      it "creates TupleType with << operator on array literal" do
        source = <<~RUBY
          arr = [1]
          arr << "string"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        converter.convert(parsed.value.statements.body[1], context)

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::TupleType)
        expect(arr_var.value.type.element_types.map(&:to_s)).to eq(%w[Integer String])
      end

      it "empty array is TupleType" do
        source = <<~RUBY
          arr = []
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::TupleType)
        expect(arr_var.value.type.element_types).to eq([])
      end

      it "widens TupleType to ArrayType on block mutation of outer variable" do
        source = <<~RUBY
          arr = [1]
          3.times { arr << "str" }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        parsed.value.statements.body.each do |stmt|
          converter.convert(stmt, context)
        end

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(arr_var.value.type.element_type.to_s).to eq("Integer | String")
      end

      it "widens empty array to ArrayType on block mutation" do
        source = <<~RUBY
          arr = []
          3.times { arr << 1 }
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        parsed.value.statements.body.each do |stmt|
          converter.convert(stmt, context)
        end

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(arr_var.value.type.element_type.to_s).to eq("Integer")
      end

      it "accumulates element_types with sequential << operations" do
        source = <<~RUBY
          arr = []
          arr << 1
          arr << "str"
          arr << :sym
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        parsed.value.statements.body.each do |stmt|
          converter.convert(stmt, context)
        end

        arr_var = context.lookup_variable(:arr)
        expect(arr_var.value.type).to be_a(TypeGuessr::Core::Types::TupleType)
        expect(arr_var.value.type.element_types.map(&:to_s)).to eq(%w[Integer String Symbol])
      end
    end
  end
end
