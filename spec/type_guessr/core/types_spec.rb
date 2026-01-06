# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::Types do
  describe "Unknown" do
    it "is a singleton" do
      unknown1 = TypeGuessr::Core::Types::Unknown.instance
      unknown2 = TypeGuessr::Core::Types::Unknown.instance
      expect(unknown1).to be(unknown2)
    end

    it "equals other Unknown instances" do
      unknown1 = TypeGuessr::Core::Types::Unknown.instance
      unknown2 = TypeGuessr::Core::Types::Unknown.instance
      expect(unknown1).to eq(unknown2)
    end

    it "does not equal other types" do
      unknown = TypeGuessr::Core::Types::Unknown.instance
      class_instance = TypeGuessr::Core::Types::ClassInstance.new("String")
      expect(unknown).not_to eq(class_instance)
    end

    it "has a string representation" do
      unknown = TypeGuessr::Core::Types::Unknown.instance
      expect(unknown.to_s).to eq("untyped")
    end
  end

  describe "ClassInstance" do
    it "stores the class name" do
      type = TypeGuessr::Core::Types::ClassInstance.new("String")
      expect(type.name).to eq("String")
    end

    it "equals another ClassInstance with the same name" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("String")
      expect(type1).to eq(type2)
    end

    it "does not equal ClassInstance with different name" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      expect(type1).not_to eq(type2)
    end

    it "has a string representation" do
      type = TypeGuessr::Core::Types::ClassInstance.new("String")
      expect(type.to_s).to eq("String")
    end

    it "formats NilClass as nil" do
      type = TypeGuessr::Core::Types::ClassInstance.new("NilClass")
      expect(type.to_s).to eq("nil")
    end

    it "formats TrueClass as true" do
      type = TypeGuessr::Core::Types::ClassInstance.new("TrueClass")
      expect(type.to_s).to eq("true")
    end

    it "formats FalseClass as false" do
      type = TypeGuessr::Core::Types::ClassInstance.new("FalseClass")
      expect(type.to_s).to eq("false")
    end
  end

  describe "Union" do
    it "creates a union of types" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      union = TypeGuessr::Core::Types::Union.new([type1, type2])
      expect(union.types).to contain_exactly(type1, type2)
    end

    it "deduplicates types" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("String")
      union = TypeGuessr::Core::Types::Union.new([type1, type2])
      expect(union.types.size).to eq(1)
    end

    it "flattens nested unions" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      type3 = TypeGuessr::Core::Types::ClassInstance.new("Float")
      inner_union = TypeGuessr::Core::Types::Union.new([type1, type2])
      outer_union = TypeGuessr::Core::Types::Union.new([inner_union, type3])
      expect(outer_union.types).to contain_exactly(type1, type2, type3)
    end

    it "removes Unknown when other types are present" do
      unknown = TypeGuessr::Core::Types::Unknown.instance
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      union = TypeGuessr::Core::Types::Union.new([unknown, type1])
      expect(union.types).to contain_exactly(type1)
    end

    it "keeps Unknown when it is the only type" do
      unknown = TypeGuessr::Core::Types::Unknown.instance
      union = TypeGuessr::Core::Types::Union.new([unknown])
      expect(union.types).to contain_exactly(unknown)
    end

    it "applies cutoff when too many types" do
      types = (1..10).map { |i| TypeGuessr::Core::Types::ClassInstance.new("Class#{i}") }
      union = TypeGuessr::Core::Types::Union.new(types, cutoff: 5)
      expect(union.types.size).to eq(5)
    end

    it "has a string representation" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      union = TypeGuessr::Core::Types::Union.new([type1, type2])
      expect(union.to_s).to match(/String \| Integer|Integer \| String/)
    end

    it "formats optional type as ?Type" do
      type = TypeGuessr::Core::Types::ClassInstance.new("String")
      nil_type = TypeGuessr::Core::Types::ClassInstance.new("NilClass")
      union = TypeGuessr::Core::Types::Union.new([type, nil_type])
      expect(union.to_s).to eq("?String")
    end

    it "formats optional type regardless of order" do
      type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      nil_type = TypeGuessr::Core::Types::ClassInstance.new("NilClass")
      union = TypeGuessr::Core::Types::Union.new([nil_type, type])
      expect(union.to_s).to eq("?Integer")
    end

    it "does not use optional format for more than 2 types" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      nil_type = TypeGuessr::Core::Types::ClassInstance.new("NilClass")
      union = TypeGuessr::Core::Types::Union.new([type1, type2, nil_type])
      expect(union.to_s).not_to start_with("?")
    end

    it "equals another Union with the same types" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      union1 = TypeGuessr::Core::Types::Union.new([type1, type2])
      union2 = TypeGuessr::Core::Types::Union.new([type2, type1])
      expect(union1).to eq(union2)
    end

    it "does not equal Union with different types" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      type3 = TypeGuessr::Core::Types::ClassInstance.new("Float")
      union1 = TypeGuessr::Core::Types::Union.new([type1, type2])
      union2 = TypeGuessr::Core::Types::Union.new([type1, type3])
      expect(union1).not_to eq(union2)
    end
  end

  describe "ArrayType" do
    it "creates an array type with element type" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      array_type = TypeGuessr::Core::Types::ArrayType.new(element_type)
      expect(array_type.element_type).to eq(element_type)
    end

    it "creates an array type with Unknown element type by default" do
      array_type = TypeGuessr::Core::Types::ArrayType.new
      expect(array_type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "equals another ArrayType with the same element type" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      array1 = TypeGuessr::Core::Types::ArrayType.new(element_type)
      array2 = TypeGuessr::Core::Types::ArrayType.new(element_type)
      expect(array1).to eq(array2)
    end

    it "does not equal ArrayType with different element type" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      array1 = TypeGuessr::Core::Types::ArrayType.new(type1)
      array2 = TypeGuessr::Core::Types::ArrayType.new(type2)
      expect(array1).not_to eq(array2)
    end

    it "has a string representation" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      array_type = TypeGuessr::Core::Types::ArrayType.new(element_type)
      expect(array_type.to_s).to eq("Array[String]")
    end

    it "has a string representation with Unknown element type" do
      array_type = TypeGuessr::Core::Types::ArrayType.new
      expect(array_type.to_s).to eq("Array[untyped]")
    end
  end

  describe "TypeVariable" do
    it "stores the type variable name" do
      type_var = described_class::TypeVariable.new(:Elem)
      expect(type_var.name).to eq(:Elem)
    end

    it "has a string representation" do
      type_var = described_class::TypeVariable.new(:U)
      expect(type_var.to_s).to eq("U")
    end

    it "equals another TypeVariable with the same name" do
      type_var1 = described_class::TypeVariable.new(:K)
      type_var2 = described_class::TypeVariable.new(:K)
      expect(type_var1).to eq(type_var2)
    end

    it "does not equal TypeVariable with different name" do
      type_var1 = described_class::TypeVariable.new(:K)
      type_var2 = described_class::TypeVariable.new(:V)
      expect(type_var1).not_to eq(type_var2)
    end
  end

  describe "HashType" do
    it "creates a hash type with key and value types" do
      key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
      value_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      hash_type = TypeGuessr::Core::Types::HashType.new(key_type, value_type)
      expect(hash_type.key_type).to eq(key_type)
      expect(hash_type.value_type).to eq(value_type)
    end

    it "creates a hash type with Unknown types by default" do
      hash_type = TypeGuessr::Core::Types::HashType.new
      expect(hash_type.key_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      expect(hash_type.value_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "has a string representation" do
      key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
      value_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      hash_type = TypeGuessr::Core::Types::HashType.new(key_type, value_type)
      expect(hash_type.to_s).to eq("Hash[Symbol, String]")
    end

    it "has a string representation with Unknown types" do
      hash_type = TypeGuessr::Core::Types::HashType.new
      expect(hash_type.to_s).to eq("Hash[untyped, untyped]")
    end

    it "equals another HashType with the same key and value types" do
      key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
      value_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      hash1 = TypeGuessr::Core::Types::HashType.new(key_type, value_type)
      hash2 = TypeGuessr::Core::Types::HashType.new(key_type, value_type)
      expect(hash1).to eq(hash2)
    end

    it "does not equal HashType with different types" do
      key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
      value_type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      value_type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      hash1 = TypeGuessr::Core::Types::HashType.new(key_type, value_type1)
      hash2 = TypeGuessr::Core::Types::HashType.new(key_type, value_type2)
      expect(hash1).not_to eq(hash2)
    end
  end

  describe "HashShape" do
    it "creates a hash shape with field types" do
      fields = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)
      expect(hash_shape.fields).to eq(fields)
    end

    it "creates an empty hash shape" do
      hash_shape = TypeGuessr::Core::Types::HashShape.new({})
      expect(hash_shape.fields).to eq({})
    end

    it "equals another HashShape with the same fields" do
      fields = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash1 = TypeGuessr::Core::Types::HashShape.new(fields)
      hash2 = TypeGuessr::Core::Types::HashShape.new(fields)
      expect(hash1).to eq(hash2)
    end

    it "does not equal HashShape with different fields" do
      fields1 = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer")
      }
      fields2 = {
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash1 = TypeGuessr::Core::Types::HashShape.new(fields1)
      hash2 = TypeGuessr::Core::Types::HashShape.new(fields2)
      expect(hash1).not_to eq(hash2)
    end

    it "has a string representation" do
      fields = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)
      # Order can vary, so we check both possibilities
      expect(hash_shape.to_s).to match(/\{ (id: Integer, name: String|name: String, id: Integer) \}/)
    end

    it "has a string representation for empty hash" do
      hash_shape = TypeGuessr::Core::Types::HashShape.new({})
      expect(hash_shape.to_s).to eq("{ }")
    end

    it "widens to generic Hash when too many fields" do
      fields = (1..20).to_h do |i|
        [:"key#{i}", TypeGuessr::Core::Types::ClassInstance.new("String")]
      end
      hash_shape = TypeGuessr::Core::Types::HashShape.new(fields, max_fields: 10)
      expect(hash_shape).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(hash_shape.name).to eq("Hash")
    end

    it "does not widen when fields are within limit" do
      fields = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash_shape = TypeGuessr::Core::Types::HashShape.new(fields, max_fields: 10)
      expect(hash_shape).to be_a(TypeGuessr::Core::Types::HashShape)
    end

    describe "#merge_field" do
      it "returns new HashShape with merged field" do
        fields = { a: TypeGuessr::Core::Types::ClassInstance.new("Integer") }
        hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)

        new_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        merged = hash_shape.merge_field(:b, new_type)

        expect(merged).to be_a(TypeGuessr::Core::Types::HashShape)
        expect(merged.fields[:a]).to eq(TypeGuessr::Core::Types::ClassInstance.new("Integer"))
        expect(merged.fields[:b]).to eq(new_type)
      end

      it "overwrites existing field" do
        fields = { a: TypeGuessr::Core::Types::ClassInstance.new("Integer") }
        hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)

        new_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        merged = hash_shape.merge_field(:a, new_type)

        expect(merged.fields[:a]).to eq(new_type)
      end

      it "widens to Hash when exceeding max_fields" do
        fields = (1..14).to_h { |i| [:"key#{i}", TypeGuessr::Core::Types::ClassInstance.new("Integer")] }
        hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)

        new_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        merged = hash_shape.merge_field(:key15, new_type)
        merged2 = merged.merge_field(:key16, new_type) if merged.is_a?(TypeGuessr::Core::Types::HashShape)

        expect(merged2).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(merged2.name).to eq("Hash")
      end

      it "does not modify original HashShape" do
        fields = { a: TypeGuessr::Core::Types::ClassInstance.new("Integer") }
        hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)

        new_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        hash_shape.merge_field(:b, new_type)

        expect(hash_shape.fields.keys).to eq([:a])
      end
    end
  end

  describe "DuckType" do
    it "creates a duck type with methods" do
      duck_type = TypeGuessr::Core::Types::DuckType.new(%i[foo bar])
      expect(duck_type.methods).to eq(%i[bar foo])
    end

    it "sorts methods alphabetically" do
      duck_type = TypeGuessr::Core::Types::DuckType.new(%i[zebra apple middle])
      expect(duck_type.methods).to eq(%i[apple middle zebra])
    end

    it "has a string representation" do
      duck_type = TypeGuessr::Core::Types::DuckType.new(%i[foo bar])
      expect(duck_type.to_s).to eq("(responds to #bar, #foo)")
    end

    it "has a string representation for single method" do
      duck_type = TypeGuessr::Core::Types::DuckType.new([:save])
      expect(duck_type.to_s).to eq("(responds to #save)")
    end

    it "equals another DuckType with the same methods" do
      duck1 = TypeGuessr::Core::Types::DuckType.new(%i[foo bar])
      duck2 = TypeGuessr::Core::Types::DuckType.new(%i[bar foo])
      expect(duck1).to eq(duck2)
    end

    it "does not equal DuckType with different methods" do
      duck1 = TypeGuessr::Core::Types::DuckType.new(%i[foo bar])
      duck2 = TypeGuessr::Core::Types::DuckType.new(%i[foo baz])
      expect(duck1).not_to eq(duck2)
    end
  end

  describe "ForwardingArgs" do
    it "is a singleton" do
      forwarding1 = TypeGuessr::Core::Types::ForwardingArgs.instance
      forwarding2 = TypeGuessr::Core::Types::ForwardingArgs.instance
      expect(forwarding1).to be(forwarding2)
    end

    it "has a string representation" do
      forwarding = TypeGuessr::Core::Types::ForwardingArgs.instance
      expect(forwarding.to_s).to eq("...")
    end
  end

  describe "#substitute" do
    let(:integer_type) { described_class::ClassInstance.new("Integer") }
    let(:string_type) { described_class::ClassInstance.new("String") }
    let(:symbol_type) { described_class::ClassInstance.new("Symbol") }

    describe "Type (base class)" do
      it "returns self by default" do
        type = integer_type
        result = type.substitute({ Elem: string_type })
        expect(result).to be(type)
      end
    end

    describe "Unknown" do
      it "returns self" do
        unknown = described_class::Unknown.instance
        result = unknown.substitute({ Elem: integer_type })
        expect(result).to be(unknown)
      end
    end

    describe "ClassInstance" do
      it "returns self (no type variables)" do
        result = integer_type.substitute({ Elem: string_type })
        expect(result).to be(integer_type)
      end
    end

    describe "TypeVariable" do
      it "returns substituted type when match found" do
        type_var = described_class::TypeVariable.new(:Elem)
        result = type_var.substitute({ Elem: integer_type })
        expect(result).to eq(integer_type)
      end

      it "returns self when no match found" do
        type_var = described_class::TypeVariable.new(:Elem)
        result = type_var.substitute({ K: integer_type })
        expect(result).to be(type_var)
      end

      it "returns self with empty substitutions" do
        type_var = described_class::TypeVariable.new(:Elem)
        result = type_var.substitute({})
        expect(result).to be(type_var)
      end
    end

    describe "ArrayType" do
      it "substitutes element type" do
        elem_var = described_class::TypeVariable.new(:Elem)
        array_type = described_class::ArrayType.new(elem_var)

        result = array_type.substitute({ Elem: integer_type })

        expect(result).to be_a(described_class::ArrayType)
        expect(result.element_type).to eq(integer_type)
      end

      it "returns self when element type unchanged" do
        array_type = described_class::ArrayType.new(integer_type)

        result = array_type.substitute({ Elem: string_type })

        expect(result).to be(array_type)
      end

      it "handles nested type variables" do
        elem_var = described_class::TypeVariable.new(:Elem)
        inner_array = described_class::ArrayType.new(elem_var)
        outer_array = described_class::ArrayType.new(inner_array)

        result = outer_array.substitute({ Elem: integer_type })

        expect(result.element_type).to be_a(described_class::ArrayType)
        expect(result.element_type.element_type).to eq(integer_type)
      end
    end

    describe "HashType" do
      it "substitutes key and value types" do
        k_var = described_class::TypeVariable.new(:K)
        v_var = described_class::TypeVariable.new(:V)
        hash_type = described_class::HashType.new(k_var, v_var)

        result = hash_type.substitute({ K: symbol_type, V: integer_type })

        expect(result).to be_a(described_class::HashType)
        expect(result.key_type).to eq(symbol_type)
        expect(result.value_type).to eq(integer_type)
      end

      it "substitutes only key type" do
        k_var = described_class::TypeVariable.new(:K)
        hash_type = described_class::HashType.new(k_var, integer_type)

        result = hash_type.substitute({ K: symbol_type })

        expect(result.key_type).to eq(symbol_type)
        expect(result.value_type).to eq(integer_type)
      end

      it "returns self when both types unchanged" do
        hash_type = described_class::HashType.new(symbol_type, integer_type)

        result = hash_type.substitute({ Elem: string_type })

        expect(result).to be(hash_type)
      end
    end

    describe "Union" do
      it "substitutes all member types" do
        elem_var = described_class::TypeVariable.new(:Elem)
        union = described_class::Union.new([elem_var, string_type])

        result = union.substitute({ Elem: integer_type })

        expect(result).to be_a(described_class::Union)
        expect(result.types).to contain_exactly(integer_type, string_type)
      end

      it "returns self when no types changed" do
        union = described_class::Union.new([integer_type, string_type])

        result = union.substitute({ Elem: symbol_type })

        expect(result).to be(union)
      end
    end

    describe "DuckType" do
      it "returns self (no type variables)" do
        duck_type = described_class::DuckType.new(%i[foo bar])
        result = duck_type.substitute({ Elem: integer_type })
        expect(result).to be(duck_type)
      end
    end

    describe "ForwardingArgs" do
      it "returns self" do
        forwarding = described_class::ForwardingArgs.instance
        result = forwarding.substitute({ Elem: integer_type })
        expect(result).to be(forwarding)
      end
    end

    describe "HashShape" do
      it "substitutes field value types" do
        elem_var = described_class::TypeVariable.new(:Elem)
        hash_shape = described_class::HashShape.new({ name: string_type, value: elem_var })

        result = hash_shape.substitute({ Elem: integer_type })

        expect(result).to be_a(described_class::HashShape)
        expect(result.fields[:name]).to eq(string_type)
        expect(result.fields[:value]).to eq(integer_type)
      end

      it "returns self when no fields changed" do
        hash_shape = described_class::HashShape.new({ name: string_type, count: integer_type })

        result = hash_shape.substitute({ Elem: symbol_type })

        expect(result).to be(hash_shape)
      end
    end
  end
end
