# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/rbs_provider"

RSpec.describe TypeGuessr::Core::RBSProvider do
  let(:provider) { described_class.new }

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
end
