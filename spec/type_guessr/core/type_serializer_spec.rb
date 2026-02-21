# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/type_serializer"

RSpec.describe TypeGuessr::Core::TypeSerializer do
  describe "round-trip serialize → deserialize" do
    shared_examples "round-trip" do |type, label|
      it "round-trips #{label}" do
        serialized = described_class.serialize(type)
        deserialized = described_class.deserialize(serialized)

        expect(deserialized).to eq(type)
      end
    end

    it_behaves_like "round-trip", TypeGuessr::Core::Types::Unknown.instance, "Unknown"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::ClassInstance.for("String"), "ClassInstance"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::SingletonType.new("File"), "SingletonType"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::ArrayType.new(TypeGuessr::Core::Types::ClassInstance.for("Integer")), "ArrayType"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::TupleType.new(
                      [TypeGuessr::Core::Types::ClassInstance.for("String"),
                       TypeGuessr::Core::Types::ClassInstance.for("Integer")]
                    ),
                    "TupleType"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::HashType.new(
                      TypeGuessr::Core::Types::ClassInstance.for("Symbol"),
                      TypeGuessr::Core::Types::ClassInstance.for("String")
                    ),
                    "HashType"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::RangeType.new(TypeGuessr::Core::Types::ClassInstance.for("Integer")),
                    "RangeType"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::HashShape.new({ name: TypeGuessr::Core::Types::ClassInstance.for("String"),
                                                             age: TypeGuessr::Core::Types::ClassInstance.for("Integer") }),
                    "HashShape"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::Union.new(
                      [TypeGuessr::Core::Types::ClassInstance.for("String"),
                       TypeGuessr::Core::Types::ClassInstance.for("Integer")]
                    ),
                    "Union"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::TypeVariable.new(:Elem), "TypeVariable"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::SelfType.instance, "SelfType"
    it_behaves_like "round-trip", TypeGuessr::Core::Types::ForwardingArgs.instance, "ForwardingArgs"
    it_behaves_like "round-trip",
                    TypeGuessr::Core::Types::MethodSignature.new(
                      [TypeGuessr::Core::Types::ParamSignature.new(
                        name: :x, kind: :required,
                        type: TypeGuessr::Core::Types::ClassInstance.for("Integer")
                      ),
                       TypeGuessr::Core::Types::ParamSignature.new(
                         name: :y, kind: :optional,
                         type: TypeGuessr::Core::Types::ClassInstance.for("String")
                       )],
                      TypeGuessr::Core::Types::ClassInstance.for("NilClass")
                    ),
                    "MethodSignature"
  end

  describe "nested types" do
    it "round-trips ArrayType(Union([ClassInstance, ArrayType]))" do
      inner = TypeGuessr::Core::Types::Union.new([
                                                   TypeGuessr::Core::Types::ClassInstance.for("String"),
                                                   TypeGuessr::Core::Types::ArrayType.new(TypeGuessr::Core::Types::ClassInstance.for("Integer")),
                                                 ])
      type = TypeGuessr::Core::Types::ArrayType.new(inner)

      deserialized = described_class.deserialize(described_class.serialize(type))

      expect(deserialized).to eq(type)
    end

    it "round-trips HashType with nested types" do
      type = TypeGuessr::Core::Types::HashType.new(
        TypeGuessr::Core::Types::ClassInstance.for("Symbol"),
        TypeGuessr::Core::Types::Union.new([
                                             TypeGuessr::Core::Types::ClassInstance.for("String"),
                                             TypeGuessr::Core::Types::ClassInstance.for("NilClass"),
                                           ])
      )

      deserialized = described_class.deserialize(described_class.serialize(type))

      expect(deserialized).to eq(type)
    end
  end

  describe ".serialize" do
    it "uses _type discriminator" do
      result = described_class.serialize(TypeGuessr::Core::Types::ClassInstance.for("String"))

      expect(result).to include("_type" => "ClassInstance")
    end

    it "serializes Unknown with no extra fields" do
      result = described_class.serialize(TypeGuessr::Core::Types::Unknown.instance)

      expect(result).to eq({ "_type" => "Unknown" })
    end
  end

  describe ".deserialize" do
    it "uses ClassInstance.for for cached instances" do
      hash = { "_type" => "ClassInstance", "name" => "String" }

      result = described_class.deserialize(hash)

      expect(result).to be(TypeGuessr::Core::Types::ClassInstance.for("String"))
    end

    it "uses .instance for Unknown singleton" do
      hash = { "_type" => "Unknown" }

      result = described_class.deserialize(hash)

      expect(result).to be(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "converts HashShape keys to symbols" do
      hash = {
        "_type" => "HashShape",
        "fields" => { "name" => { "_type" => "ClassInstance", "name" => "String" } }
      }

      result = described_class.deserialize(hash)

      expect(result.fields.keys).to all(be_a(Symbol))
    end

    it "converts TypeVariable name to symbol" do
      hash = { "_type" => "TypeVariable", "name" => "Elem" }

      result = described_class.deserialize(hash)

      expect(result.name).to eq(:Elem)
    end

    it "raises on unknown _type" do
      hash = { "_type" => "NonExistent" }

      expect { described_class.deserialize(hash) }.to raise_error(ArgumentError, /Unknown type/)
    end
  end
end
