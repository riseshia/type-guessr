# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/literal_type_analyzer"

RSpec.describe TypeGuessr::Core::LiteralTypeAnalyzer do
  describe ".infer" do
    it "infers Integer from integer literal" do
      code = "42"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Integer")
    end

    it "infers Float from float literal" do
      code = "3.14"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Float")
    end

    it "infers String from string literal" do
      code = '"hello"'
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("String")
    end

    it "infers String from interpolated string literal" do
      code = '"hello #{world}"'
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("String")
    end

    it "infers Symbol from symbol literal" do
      code = ":foo"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Symbol")
    end

    it "infers TrueClass from true literal" do
      code = "true"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("TrueClass")
    end

    it "infers FalseClass from false literal" do
      code = "false"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("FalseClass")
    end

    it "infers NilClass from nil literal" do
      code = "nil"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("NilClass")
    end

    it "infers ArrayType from array literal" do
      code = "[1, 2, 3]"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
    end

    # Array element type inference tests
    describe "array element type inference" do
      # Rule 1: Homogeneous literals → typed array
      it "infers Array[Integer] from homogeneous integer array" do
        code = "[1, 2, 3]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("Integer")
      end

      it "infers Array[String] from homogeneous string array" do
        code = '["a", "b", "c"]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end

      it "infers Array[Symbol] from homogeneous symbol array" do
        code = "[:a, :b, :c]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("Symbol")
      end

      # Rule 2: Mixed literals (2-3 types) → Union
      it "infers Array[Integer | String] from mixed array with 2 types" do
        code = '[1, "hello"]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::Union)
        expect(type.element_type.types.size).to eq(2)
        type_names = type.element_type.types.map(&:name).sort
        expect(type_names).to eq(%w[Integer String])
      end

      it "infers Array[Integer | String | Symbol] from mixed array with 3 types" do
        code = '[1, "hello", :symbol]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::Union)
        expect(type.element_type.types.size).to eq(3)
        type_names = type.element_type.types.map(&:name).sort
        expect(type_names).to eq(%w[Integer String Symbol])
      end

      # Rule 3: Mixed literals (4+ types) → untyped
      it "infers Array[untyped] from mixed array with 4+ types" do
        code = '[1, "hello", :symbol, true]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end

      # Rule 4: Empty → untyped
      it "infers Array[untyped] from empty array" do
        code = "[]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end

      # Rule 5: Nested → 1 level only
      it "infers Array[Array[Integer]] from nested homogeneous array" do
        code = "[[1, 2], [3, 4]]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.element_type.name).to eq("Integer")
      end

      it "infers Array[Array[untyped]] from deeply nested array (2+ levels)" do
        code = "[[[1, 2]]]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end

      # Rule 6: Non-literal elements → skip (returns untyped for that element)
      it "infers Array[untyped] when array contains non-literal elements" do
        code = "[foo.bar, baz]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        # Non-literals can't be inferred, so we get untyped
        expect(type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end

      it "infers Array[String] when array has mixed literals and non-literals but literals are homogeneous" do
        code = '["hello", foo.bar, "world"]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        # Skip non-literals, infer from remaining homogeneous literals (pragmatic!)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("String")
      end

      # Rule 7: Performance limit (max 5 samples)
      it "samples only first 5 elements for large arrays" do
        code = "[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]"
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(type.element_type.name).to eq("Integer")
      end

      it "detects mixed types within first 5 samples" do
        code = '[1, "a", 2, "b", 3, 6, 7, 8]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(type.element_type).to be_a(TypeGuessr::Core::Types::Union)
        expect(type.element_type.types.size).to eq(2)
      end

      it "stops at 4+ unique types even if more samples available" do
        code = '[1, "a", :b, true, false, nil, 1.0]'
        node = Prism.parse(code).value.statements.body.first
        type = described_class.infer(node)

        expect(type).to be_a(TypeGuessr::Core::Types::ArrayType)
        # First 5 elements: 1, "a", :b, true, false → 4 types → untyped
        expect(type.element_type).to eq(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    it "infers Hash from hash literal" do
      code = "{ a: 1 }"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Hash")
    end

    it "infers Range from range literal" do
      code = "1..10"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Range")
    end

    it "infers Regexp from regexp literal" do
      code = "/pattern/"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(type.name).to eq("Regexp")
    end

    it "returns nil for non-literal nodes" do
      code = "foo.bar"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_nil
    end

    it "returns nil for variable nodes" do
      code = "some_var"
      node = Prism.parse(code).value.statements.body.first
      type = described_class.infer(node)

      expect(type).to be_nil
    end
  end
end
