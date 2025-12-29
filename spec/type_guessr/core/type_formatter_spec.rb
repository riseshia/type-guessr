# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/type_formatter"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::TypeFormatter do
  describe ".format" do
    it "formats Unknown as untyped" do
      unknown = TypeGuessr::Core::Types::Unknown.instance
      expect(described_class.format(unknown)).to eq("untyped")
    end

    it "formats ClassInstance as class name" do
      type = TypeGuessr::Core::Types::ClassInstance.new("String")
      expect(described_class.format(type)).to eq("String")
    end

    it "formats NilClass as nil" do
      type = TypeGuessr::Core::Types::ClassInstance.new("NilClass")
      expect(described_class.format(type)).to eq("nil")
    end

    it "formats TrueClass as true" do
      type = TypeGuessr::Core::Types::ClassInstance.new("TrueClass")
      expect(described_class.format(type)).to eq("true")
    end

    it "formats FalseClass as false" do
      type = TypeGuessr::Core::Types::ClassInstance.new("FalseClass")
      expect(described_class.format(type)).to eq("false")
    end

    it "formats Union with pipe separator" do
      type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
      type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      union = TypeGuessr::Core::Types::Union.new([type1, type2])

      result = described_class.format(union)
      # Order may vary, check both possibilities
      expect(result).to match(/^(String \| Integer|Integer \| String)$/)
    end

    it "formats ArrayType with element type" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      array_type = TypeGuessr::Core::Types::ArrayType.new(element_type)

      expect(described_class.format(array_type)).to eq("Array[String]")
    end

    it "formats ArrayType with Unknown element as Array[untyped]" do
      array_type = TypeGuessr::Core::Types::ArrayType.new
      expect(described_class.format(array_type)).to eq("Array[untyped]")
    end

    it "formats HashShape with field types" do
      fields = {
        id: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
        name: TypeGuessr::Core::Types::ClassInstance.new("String")
      }
      hash_shape = TypeGuessr::Core::Types::HashShape.new(fields)

      result = described_class.format(hash_shape)
      # Order may vary
      expect(result).to match(/^\{ (id: Integer, name: String|name: String, id: Integer) \}$/)
    end

    it "formats empty HashShape" do
      hash_shape = TypeGuessr::Core::Types::HashShape.new({})
      expect(described_class.format(hash_shape)).to eq("{ }")
    end

    it "formats nested types" do
      string_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      array_type = TypeGuessr::Core::Types::ArrayType.new(string_type)
      integer_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      union = TypeGuessr::Core::Types::Union.new([array_type, integer_type])

      result = described_class.format(union)
      # Check that it contains both Array[String] and Integer
      expect(result).to include("Array[String]")
      expect(result).to include("Integer")
      expect(result).to include("|")
    end
  end
end
