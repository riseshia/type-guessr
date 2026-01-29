# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/registry/signature_registry"

RSpec.describe TypeGuessr::Core::Registry::SignatureRegistry do
  # rubocop:disable RSpec/DescribedClass
  # Use explicit class reference to avoid described_class changing in nested describes
  let(:registry) { TypeGuessr::Core::Registry::SignatureRegistry.instance.preload }
  # rubocop:enable RSpec/DescribedClass

  describe "#preload" do
    it "loads stdlib RBS methods" do
      # Singleton is preloaded via registry let block
      expect(registry.preloaded?).to be(true)
    end

    it "returns self for chaining" do
      result = registry.preload

      expect(result).to be(registry)
    end

    it "is idempotent" do
      registry.preload
      registry.preload

      expect(registry.preloaded?).to be(true)
    end
  end

  describe "#lookup" do
    it "returns MethodEntry for known stdlib method" do
      entry = registry.lookup("String", "upcase")

      expect(entry).to be_a(described_class::MethodEntry)
    end

    it "returns nil for unknown class" do
      entry = registry.lookup("NonExistentClass", "method")

      expect(entry).to be_nil
    end

    it "returns nil for unknown method" do
      entry = registry.lookup("String", "non_existent_method")

      expect(entry).to be_nil
    end
  end

  describe "#lookup_class_method" do
    it "returns MethodEntry for known class method" do
      entry = registry.lookup_class_method("File", "read")

      expect(entry).to be_a(described_class::MethodEntry)
    end

    it "returns nil for unknown class method" do
      entry = registry.lookup_class_method("String", "non_existent")

      expect(entry).to be_nil
    end
  end

  describe "#get_method_return_type" do
    describe "simple types" do
      it "returns String for String#upcase" do
        type = registry.get_method_return_type("String", "upcase")

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("String")
      end

      it "returns Integer for String#length" do
        type = registry.get_method_return_type("String", "length")

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Integer")
      end

      it "returns Unknown for non-existent method" do
        type = registry.get_method_return_type("String", "non_existent")

        expect(type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    describe "generic types" do
      it "returns Array[String] for String#chars" do
        type = registry.get_method_return_type("String", "chars")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end

      it "returns Array[Elem] for Array#compact (type variable Elem)" do
        type = registry.get_method_return_type("Array", "compact")

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::TypeVariable)
        expect(type.element_type.name).to eq(:Elem)
      end
    end
  end

  describe "#get_class_method_return_type" do
    it "returns String for File.read" do
      type = registry.get_class_method_return_type("File", "read")

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("String")
    end

    it "returns Unknown for non-existent class method" do
      type = registry.get_class_method_return_type("String", "non_existent")

      expect(type).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end
  end

  describe "#get_block_param_types" do
    it "returns block parameter types for Array#each" do
      types = registry.get_block_param_types("Array", "each")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::TypeVariable)
      expect(types.first.name).to eq(:Elem)
    end

    it "returns block parameter types for Array#map" do
      types = registry.get_block_param_types("Array", "map")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::TypeVariable)
      expect(types.first.name).to eq(:Elem)
    end

    it "returns empty array for method without block" do
      types = registry.get_block_param_types("String", "upcase")

      expect(types).to eq([])
    end

    it "returns empty array for non-existent method" do
      types = registry.get_block_param_types("String", "non_existent")

      expect(types).to eq([])
    end

    it "returns concrete types for String#each_char" do
      types = registry.get_block_param_types("String", "each_char")

      expect(types).to be_an(Array)
      expect(types.size).to eq(1)
      expect(types.first).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(types.first.name).to eq("String")
    end
  end

  describe "#get_method_signatures" do
    it "returns method signatures for known method" do
      signatures = registry.get_method_signatures("String", "upcase")

      expect(signatures).not_to be_empty
      expect(signatures.first).to be_a(described_class::Signature)
      expect(signatures.first.method_type).to be_a(RBS::MethodType)
    end

    it "returns empty array for unknown method" do
      signatures = registry.get_method_signatures("String", "non_existent")

      expect(signatures).to eq([])
    end

    it "handles overloaded methods" do
      signatures = registry.get_method_signatures("Array", "[]")

      expect(signatures.size).to be >= 1
    end
  end

  describe "#get_class_method_signatures" do
    it "returns signatures for class methods" do
      signatures = registry.get_class_method_signatures("File", "read")

      expect(signatures).not_to be_empty
      expect(signatures.first).to be_a(described_class::Signature)
    end

    it "returns empty array for unknown class method" do
      signatures = registry.get_class_method_signatures("String", "non_existent")

      expect(signatures).to eq([])
    end
  end

  describe "overload resolution with arg_types" do
    describe "Integer arithmetic" do
      let(:int_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
      let(:float_type) { TypeGuessr::Core::Types::ClassInstance.new("Float") }

      it "returns Integer for Integer#* with Integer argument" do
        type = registry.get_method_return_type("Integer", "*", [int_type])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Integer")
      end

      it "returns Float for Integer#* with Float argument" do
        type = registry.get_method_return_type("Integer", "*", [float_type])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Float")
      end

      it "returns Integer for Integer#+ with Integer argument" do
        type = registry.get_method_return_type("Integer", "+", [int_type])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Integer")
      end

      it "returns Float for Integer#+ with Float argument" do
        type = registry.get_method_return_type("Integer", "+", [float_type])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("Float")
      end
    end

    describe "with no arguments" do
      it "falls back to first overload" do
        type = registry.get_method_return_type("Integer", "*", [])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type).not_to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    describe "with Unknown argument types" do
      it "falls back to first overload when argument type is Unknown" do
        unknown_type = TypeGuessr::Core::Types::Unknown.instance
        type = registry.get_method_return_type("Integer", "*", [unknown_type])

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type).not_to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end
  end

  describe described_class::MethodEntry do
    # Get entry via lookup instead of direct instantiation
    let(:string_upcase_entry) { registry.lookup("String", "upcase") }
    let(:array_each_entry) { registry.lookup("Array", "each") }

    describe "#return_type" do
      it "returns the method return type" do
        type = string_upcase_entry.return_type

        expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.name).to eq("String")
      end
    end

    describe "#block_param_types" do
      it "returns block parameter types" do
        types = array_each_entry.block_param_types

        expect(types).to be_an(Array)
        expect(types.size).to eq(1)
      end

      it "caches the result" do
        first_call = array_each_entry.block_param_types
        second_call = array_each_entry.block_param_types

        expect(first_call).to be(second_call)
      end
    end

    describe "#signatures" do
      it "returns raw RBS method types" do
        signatures = string_upcase_entry.signatures

        expect(signatures).to be_an(Array)
        expect(signatures.first).to be_a(RBS::MethodType)
      end
    end
  end
end
