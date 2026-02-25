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

  describe described_class::GemMethodEntry do
    let(:return_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
    let(:params) do
      [
        TypeGuessr::Core::Types::ParamSignature.new(
          name: :name, kind: :required, type: TypeGuessr::Core::Types::ClassInstance.new("String")
        ),
      ]
    end

    describe "#return_type" do
      it "returns the stored return type" do
        entry = described_class.new(return_type)

        expect(entry.return_type).to eq(return_type)
      end

      it "ignores arg_types parameter" do
        entry = described_class.new(return_type)
        int_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")

        expect(entry.return_type([int_type])).to eq(return_type)
      end
    end

    describe "#block_param_types" do
      it "always returns empty array" do
        entry = described_class.new(return_type)

        expect(entry.block_param_types).to eq([])
      end
    end

    describe "#type_params" do
      it "always returns empty array" do
        entry = described_class.new(return_type)

        expect(entry.type_params).to eq([])
      end
    end

    describe "#block_return_type_var" do
      it "always returns nil" do
        entry = described_class.new(return_type)

        expect(entry.block_return_type_var).to be_nil
      end
    end

    describe "#signatures" do
      it "always returns empty array" do
        entry = described_class.new(return_type)

        expect(entry.signatures).to eq([])
      end
    end

    describe "#signature_strings" do
      it "returns formatted signature with params" do
        entry = described_class.new(return_type, params)

        expect(entry.signature_strings).to eq(["(String name) -> String"])
      end

      it "returns formatted signature without params" do
        entry = described_class.new(return_type)

        expect(entry.signature_strings).to eq(["() -> String"])
      end

      it "returns formatted signature with Unguessed types" do
        unguessed = TypeGuessr::Core::Types::Unguessed.instance
        unguessed_params = [
          TypeGuessr::Core::Types::ParamSignature.new(
            name: :x, kind: :required, type: unguessed
          ),
        ]
        entry = described_class.new(unguessed, unguessed_params)

        expect(entry.signature_strings).to eq(["(unguessed x) -> unguessed"])
      end
    end

    describe "#params" do
      it "returns the stored params" do
        entry = described_class.new(return_type, params)

        expect(entry.params).to eq(params)
      end

      it "defaults to empty array" do
        entry = described_class.new(return_type)

        expect(entry.params).to eq([])
      end
    end
  end

  describe "#register_gem_method" do
    it "registers a gem instance method" do
      return_type = TypeGuessr::Core::Types::ClassInstance.new("MyGemClass")
      registry.register_gem_method("MyGemClass", "my_method", return_type)

      entry = registry.lookup("MyGemClass", "my_method")

      expect(entry).to be_a(described_class::GemMethodEntry)
      expect(entry.return_type).to eq(return_type)
    end

    it "does not overwrite existing RBS entry" do
      # String#upcase is already loaded via RBS preload
      return_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      registry.register_gem_method("String", "upcase", return_type)

      entry = registry.lookup("String", "upcase")

      expect(entry).to be_a(described_class::MethodEntry)
    end

    it "registers with params" do
      return_type = TypeGuessr::Core::Types::ClassInstance.new("Boolean")
      params = [
        TypeGuessr::Core::Types::ParamSignature.new(
          name: :key, kind: :req, type: TypeGuessr::Core::Types::ClassInstance.new("String")
        ),
      ]
      registry.register_gem_method("MyGemClass", "check", return_type, params)

      entry = registry.lookup("MyGemClass", "check")

      expect(entry.params.size).to eq(1)
      expect(entry.params.first.name).to eq(:key)
    end
  end

  describe "#register_gem_class_method" do
    it "registers a gem class method" do
      return_type = TypeGuessr::Core::Types::ClassInstance.new("MyGemClass")
      registry.register_gem_class_method("MyGemClass", "create", return_type)

      entry = registry.lookup_class_method("MyGemClass", "create")

      expect(entry).to be_a(described_class::GemMethodEntry)
      expect(entry.return_type).to eq(return_type)
    end

    it "does not overwrite existing RBS entry" do
      # File.read is already loaded via RBS preload
      return_type = TypeGuessr::Core::Types::ClassInstance.new("Integer")
      registry.register_gem_class_method("File", "read", return_type)

      entry = registry.lookup_class_method("File", "read")

      expect(entry).to be_a(described_class::MethodEntry)
    end
  end

  describe "#load_gem_cache" do
    it "bulk loads instance methods from cache data" do
      cache_data = {
        "GemFoo" => {
          "bar" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "String" },
            "params" => [
              { "name" => "x", "kind" => "req", "type" => { "_type" => "ClassInstance", "name" => "Integer" } },
            ]
          }
        }
      }

      registry.load_gem_cache(cache_data, kind: :instance)

      entry = registry.lookup("GemFoo", "bar")

      expect(entry).to be_a(described_class::GemMethodEntry)
      expect(entry.return_type).to eq(TypeGuessr::Core::Types::ClassInstance.new("String"))
      expect(entry.params.size).to eq(1)
      expect(entry.params.first.name).to eq(:x)
      expect(entry.params.first.kind).to eq(:req)
    end

    it "bulk loads class methods from cache data" do
      cache_data = {
        "GemFoo" => {
          "create" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "GemFoo" },
            "params" => []
          }
        }
      }

      registry.load_gem_cache(cache_data, kind: :class)

      entry = registry.lookup_class_method("GemFoo", "create")

      expect(entry).to be_a(described_class::GemMethodEntry)
      expect(entry.return_type).to eq(TypeGuessr::Core::Types::ClassInstance.new("GemFoo"))
    end

    it "does not overwrite existing RBS entries" do
      cache_data = {
        "String" => {
          "upcase" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "Integer" }
          }
        }
      }

      registry.load_gem_cache(cache_data, kind: :instance)

      entry = registry.lookup("String", "upcase")

      expect(entry).to be_a(described_class::MethodEntry)
    end

    it "handles entries without params key" do
      cache_data = {
        "GemBar" => {
          "baz" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "NilClass" }
          }
        }
      }

      registry.load_gem_cache(cache_data, kind: :instance)

      entry = registry.lookup("GemBar", "baz")

      expect(entry.params).to eq([])
    end
  end

  describe "on-demand inference" do
    after { registry.on_demand_inferrer = nil }

    describe "#get_method_return_type with Unguessed entry" do
      it "triggers on_demand_inferrer when return type is Unguessed" do
        registry.register_gem_method("OnDemandFoo", "bar", TypeGuessr::Core::Types::Unguessed.instance)
        called_with = nil
        registry.on_demand_inferrer = ->(cn, mn, kind) { called_with = [cn, mn, kind] }

        registry.get_method_return_type("OnDemandFoo", "bar")

        expect(called_with).to eq(["OnDemandFoo", "bar", :instance])
      end

      it "returns inferred type after on-demand callback replaces entry" do
        registry.register_gem_method("OnDemandFoo2", "bar", TypeGuessr::Core::Types::Unguessed.instance)
        registry.on_demand_inferrer = lambda { |_cn, _mn, _kind|
          registry.replace_unguessed_entries(
            { "OnDemandFoo2" => { "bar" => {
              "return_type" => { "_type" => "ClassInstance", "name" => "String" },
              "params" => []
            } } },
            kind: :instance
          )
        }

        result = registry.get_method_return_type("OnDemandFoo2", "bar")

        expect(result).to eq(TypeGuessr::Core::Types::ClassInstance.for("String"))
      end

      it "returns Unknown when no on_demand_inferrer is set" do
        registry.register_gem_method("OnDemandFoo3", "bar", TypeGuessr::Core::Types::Unguessed.instance)

        result = registry.get_method_return_type("OnDemandFoo3", "bar")

        expect(result).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    describe "#get_class_method_return_type with Unguessed entry" do
      it "triggers on_demand_inferrer for class methods" do
        registry.register_gem_class_method("OnDemandBar", "create", TypeGuessr::Core::Types::Unguessed.instance)
        called_with = nil
        registry.on_demand_inferrer = ->(cn, mn, kind) { called_with = [cn, mn, kind] }

        registry.get_class_method_return_type("OnDemandBar", "create")

        expect(called_with).to eq(["OnDemandBar", "create", :class])
      end

      it "returns inferred type after on-demand callback replaces class method entry" do
        registry.register_gem_class_method("OnDemandBar2", "create", TypeGuessr::Core::Types::Unguessed.instance)
        registry.on_demand_inferrer = lambda { |_cn, _mn, _kind|
          registry.replace_unguessed_entries(
            { "OnDemandBar2" => { "create" => {
              "return_type" => { "_type" => "ClassInstance", "name" => "OnDemandBar2" },
              "params" => []
            } } },
            kind: :class
          )
        }

        result = registry.get_class_method_return_type("OnDemandBar2", "create")

        expect(result).to eq(TypeGuessr::Core::Types::ClassInstance.for("OnDemandBar2"))
      end
    end

    describe "#replace_unguessed_entries" do
      it "replaces Unguessed GemMethodEntry with inferred type" do
        registry.register_gem_method("ReplaceTest", "foo", TypeGuessr::Core::Types::Unguessed.instance)

        registry.replace_unguessed_entries(
          { "ReplaceTest" => { "foo" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "Integer" },
            "params" => [{ "name" => "x", "kind" => "required", "type" => { "_type" => "ClassInstance", "name" => "String" } }]
          } } },
          kind: :instance
        )

        entry = registry.lookup("ReplaceTest", "foo")

        expect(entry.return_type).to eq(TypeGuessr::Core::Types::ClassInstance.for("Integer"))
        expect(entry.params.size).to eq(1)
        expect(entry.params.first.name).to eq(:x)
      end

      it "does not replace non-Unguessed GemMethodEntry" do
        registry.register_gem_method("ReplaceTest2", "foo",
                                     TypeGuessr::Core::Types::ClassInstance.for("String"))

        registry.replace_unguessed_entries(
          { "ReplaceTest2" => { "foo" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "Integer" },
            "params" => []
          } } },
          kind: :instance
        )

        entry = registry.lookup("ReplaceTest2", "foo")

        expect(entry.return_type).to eq(TypeGuessr::Core::Types::ClassInstance.for("String"))
      end

      it "does not replace RBS MethodEntry" do
        # String#upcase is an RBS entry
        registry.replace_unguessed_entries(
          { "String" => { "upcase" => {
            "return_type" => { "_type" => "ClassInstance", "name" => "Integer" },
            "params" => []
          } } },
          kind: :instance
        )

        entry = registry.lookup("String", "upcase")

        expect(entry).to be_a(described_class::MethodEntry)
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

    describe "#type_params" do
      it "returns [:U] for Array#map" do
        entry = registry.lookup("Array", "map")

        expect(entry.type_params).to eq([:U])
      end

      it "returns [:X] for Thread::Mutex#synchronize" do
        entry = registry.lookup("Thread::Mutex", "synchronize")

        expect(entry.type_params).to eq([:X])
      end

      it "returns [] for String#upcase" do
        expect(string_upcase_entry.type_params).to eq([])
      end
    end

    describe "#block_return_type_var" do
      it "returns :U for Array#map" do
        entry = registry.lookup("Array", "map")

        expect(entry.block_return_type_var).to eq(:U)
      end

      it "returns :X for Thread::Mutex#synchronize" do
        entry = registry.lookup("Thread::Mutex", "synchronize")

        expect(entry.block_return_type_var).to eq(:X)
      end

      it "returns nil for String#upcase (no block)" do
        expect(string_upcase_entry.block_return_type_var).to be_nil
      end

      it "returns :U for Array#filter_map (union nil | false | U)" do
        entry = registry.lookup("Array", "filter_map")

        expect(entry.block_return_type_var).to eq(:U)
      end
    end

    describe "#signatures" do
      it "returns raw RBS method types" do
        signatures = string_upcase_entry.signatures

        expect(signatures).to be_an(Array)
        expect(signatures.first).to be_a(RBS::MethodType)
      end
    end

    describe "#signature_strings" do
      it "returns formatted RBS method type strings" do
        strings = string_upcase_entry.signature_strings

        expect(strings).to be_an(Array)
        expect(strings).not_to be_empty
        expect(strings.first).to be_a(String)
      end
    end
  end
end
