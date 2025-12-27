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
