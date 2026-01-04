# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/rbs_converter"
require "rbs"

RSpec.describe TypeGuessr::Core::Converter::RBSConverter do
  let(:converter) { described_class.new }

  describe "#convert" do
    context "with ClassInstance types" do
      it "converts simple class type" do
        rbs_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.name).to eq("String")
      end

      it "converts Array with element type" do
        elem_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        rbs_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Array, namespace: RBS::Namespace.root),
          args: [elem_type],
          location: nil
        )

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.element_type.name).to eq("String")
      end

      it "converts Array with type variable as element" do
        var_type = RBS::Types::Variable.new(name: :Elem, location: nil)
        rbs_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Array, namespace: RBS::Namespace.root),
          args: [var_type],
          location: nil
        )

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::TypeVariable)
        expect(result.element_type.name).to eq(:Elem)
      end
    end

    context "with Union types" do
      it "converts union of simple types" do
        string_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        integer_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        rbs_type = RBS::Types::Union.new(
          types: [string_type, integer_type],
          location: nil
        )

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.types.size).to eq(2)
        expect(result.types.map(&:name)).to contain_exactly("String", "Integer")
      end
    end

    context "with TypeVariable" do
      it "converts type variable without substitution" do
        rbs_type = RBS::Types::Variable.new(name: :U, location: nil)

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::TypeVariable)
        expect(result.name).to eq(:U)
      end

      it "applies substitution when provided" do
        rbs_type = RBS::Types::Variable.new(name: :Elem, location: nil)
        substitutions = { Elem: TypeGuessr::Core::Types::ClassInstance.new("String") }

        result = converter.convert(rbs_type, substitutions)
        expect(result).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.name).to eq("String")
      end
    end

    context "with Tuple types" do
      it "converts tuple to Array with union element type" do
        string_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        integer_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Integer, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        rbs_type = RBS::Types::Tuple.new(
          types: [string_type, integer_type],
          location: nil
        )

        result = converter.convert(rbs_type)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.element_type.types.size).to eq(2)
      end

      it "applies substitution to tuple elements" do
        var1 = RBS::Types::Variable.new(name: :K, location: nil)
        var2 = RBS::Types::Variable.new(name: :V, location: nil)
        rbs_type = RBS::Types::Tuple.new(
          types: [var1, var2],
          location: nil
        )
        substitutions = {
          K: TypeGuessr::Core::Types::ClassInstance.new("Symbol"),
          V: TypeGuessr::Core::Types::ClassInstance.new("String")
        }

        result = converter.convert(rbs_type, substitutions)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.element_type.types.map(&:name)).to contain_exactly("Symbol", "String")
      end
    end

    context "with Self and Instance types" do
      it "converts Self to Unknown" do
        rbs_type = RBS::Types::Bases::Self.new(location: nil)

        result = converter.convert(rbs_type)
        expect(result).to be(TypeGuessr::Core::Types::Unknown.instance)
      end

      it "converts Instance to Unknown" do
        rbs_type = RBS::Types::Bases::Instance.new(location: nil)

        result = converter.convert(rbs_type)
        expect(result).to be(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    context "with nested generic types" do
      it "converts Array[Array[String]]" do
        string_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :String, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        inner_array = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Array, namespace: RBS::Namespace.root),
          args: [string_type],
          location: nil
        )
        outer_array = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Array, namespace: RBS::Namespace.root),
          args: [inner_array],
          location: nil
        )

        result = converter.convert(outer_array)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.element_type.element_type.name).to eq("String")
      end
    end

    context "with type variable substitution in complex types" do
      it "substitutes type variable in Array[U]" do
        var_type = RBS::Types::Variable.new(name: :U, location: nil)
        rbs_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :Array, namespace: RBS::Namespace.root),
          args: [var_type],
          location: nil
        )
        substitutions = { U: TypeGuessr::Core::Types::ClassInstance.new("Integer") }

        result = converter.convert(rbs_type, substitutions)
        expect(result).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.element_type.name).to eq("Integer")
      end

      it "substitutes type variable in Union" do
        var_type = RBS::Types::Variable.new(name: :T, location: nil)
        nil_type = RBS::Types::ClassInstance.new(
          name: RBS::TypeName.new(name: :NilClass, namespace: RBS::Namespace.root),
          args: [],
          location: nil
        )
        rbs_type = RBS::Types::Union.new(
          types: [var_type, nil_type],
          location: nil
        )
        substitutions = { T: TypeGuessr::Core::Types::ClassInstance.new("String") }

        result = converter.convert(rbs_type, substitutions)
        expect(result).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.types.map(&:name)).to contain_exactly("String", "NilClass")
      end
    end
  end
end
