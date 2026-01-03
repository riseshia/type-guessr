# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/rbs_provider"

RSpec.describe TypeGuessr::Core::RBSProvider do
  let(:provider) { described_class.instance }

  describe "#get_method_signatures" do
    it "returns method signatures from RBS for known stdlib classes" do
      signatures = provider.get_method_signatures("String", "upcase")

      expect(signatures).not_to be_empty
      expect(signatures).to be_an(Array)
    end

    it "returns empty array for non-existent class" do
      signatures = provider.get_method_signatures("NonExistentClass", "method")

      expect(signatures).to eq([])
    end

    it "returns empty array for non-existent method" do
      signatures = provider.get_method_signatures("String", "non_existent_method")

      expect(signatures).to eq([])
    end

    it "handles overloaded methods" do
      # Array#[] has multiple signatures
      signatures = provider.get_method_signatures("Array", "[]")

      expect(signatures.size).to be >= 1
    end
  end

  describe "lazy loading" do
    it "loads RBS environment only once" do
      # First call loads environment
      provider.get_method_signatures("String", "upcase")

      # Second call should use cached environment
      # We can't easily test memoization directly, but we can verify it works
      signatures = provider.get_method_signatures("String", "downcase")

      expect(signatures).not_to be_empty
    end
  end

  describe "signature representation" do
    it "returns signature objects with method information" do
      signatures = provider.get_method_signatures("String", "upcase")

      signature = signatures.first
      expect(signature).to respond_to(:method_type)
    end
  end

  describe "#get_method_return_type" do
    describe "simple types" do
      it "returns String for String#upcase" do
        type = provider.get_method_return_type("String", "upcase")

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("String")
      end

      it "returns Integer for String#length" do
        type = provider.get_method_return_type("String", "length")

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Integer")
      end

      it "returns Unknown for non-existent method" do
        type = provider.get_method_return_type("String", "non_existent")

        expect(type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    describe "generic types" do
      it "returns Array[String] for String#chars" do
        type = provider.get_method_return_type("String", "chars")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end

      it "returns Array[String] for String#split" do
        type = provider.get_method_return_type("String", "split")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end

      it "returns Array[untyped] for Array#compact (type variable Elem)" do
        # Array#compact returns Array[Elem], but Elem is a type variable
        # Without substitution, we can't resolve it, so return Array[untyped]
        type = provider.get_method_return_type("Array", "compact")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        # Type variable can't be resolved without context, so element is Unknown
        expect(type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end

      it "handles nested generic types" do
        # String#lines returns Array[String]
        type = provider.get_method_return_type("String", "lines")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end
    end
  end

  describe "#get_block_param_types" do
    it "returns block parameter types for Array#each" do
      # Array#each { |item| ... } - item is Elem (type variable)
      types = provider.get_block_param_types("Array", "each")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      # Without substitution, Elem is Unknown
      expect(types.first).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "returns block parameter types for Array#map" do
      # Array#map { |item| ... } - item is Elem (type variable)
      types = provider.get_block_param_types("Array", "map")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "returns empty array for method without block" do
      types = provider.get_block_param_types("String", "upcase")

      expect(types).to eq([])
    end

    it "returns empty array for non-existent method" do
      types = provider.get_block_param_types("String", "non_existent")

      expect(types).to eq([])
    end

    it "returns concrete types for String#each_char" do
      # String#each_char { |char| ... } - char is String
      types = provider.get_block_param_types("String", "each_char")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(types.first.name).to eq("String")
    end
  end

  describe "#get_block_param_types_with_substitution" do
    it "substitutes Elem with actual element type for Array#each" do
      # If we know Array[Integer], then Elem -> Integer
      element_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      types = provider.get_block_param_types_with_substitution("Array", "each", elem: element_type)

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(types.first.name).to eq("Integer")
    end

    it "substitutes Elem with actual element type for Array#map" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("String")
      types = provider.get_block_param_types_with_substitution("Array", "map", elem: element_type)

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(types.first.name).to eq("String")
    end

    it "handles methods without type variables" do
      # String#each_char already has concrete type, no substitution needed
      types = provider.get_block_param_types_with_substitution("String", "each_char", elem: nil)

      expect(types.size).to eq(1)
      expect(types.first.name).to eq("String")
    end

    it "returns empty array for method without block" do
      element_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      types = provider.get_block_param_types_with_substitution("String", "upcase", elem: element_type)

      expect(types).to eq([])
    end

    describe "Hash type variable substitution" do
      it "substitutes K and V for Hash#each" do
        key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
        value_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
        types = provider.get_block_param_types_with_substitution(
          "Hash", "each", key: key_type, value: value_type
        )

        expect(types).to be_an(Array)
        expect(types.size).to eq(1)
        # Hash#each yields [K, V] as tuple, which becomes ArrayType with Union
        expect(types.first).to be_a(TypeGuessr::Core::Types::ArrayType)
      end

      it "substitutes K for Hash#each_key" do
        key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
        value_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
        types = provider.get_block_param_types_with_substitution(
          "Hash", "each_key", key: key_type, value: value_type
        )

        expect(types).to be_an(Array)
        expect(types.size).to eq(1)
        expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(types.first.name).to eq("Symbol")
      end

      it "substitutes V for Hash#each_value" do
        key_type = TypeGuessr::Core::Types::ClassInstance.new("Symbol")
        value_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
        types = provider.get_block_param_types_with_substitution(
          "Hash", "each_value", key: key_type, value: value_type
        )

        expect(types).to be_an(Array)
        expect(types.size).to eq(1)
        expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(types.first.name).to eq("Integer")
      end
    end
  end
end
