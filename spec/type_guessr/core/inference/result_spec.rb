# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/inference/result"

RSpec.describe TypeGuessr::Core::Inference::Result do
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }

  describe "#initialize" do
    it "stores type, reason, and source" do
      result = described_class.new(string_type, "literal assignment", :literal)

      expect(result.type).to eq(string_type)
      expect(result.reason).to eq("literal assignment")
      expect(result.source).to eq(:literal)
    end

    it "defaults source to :unknown" do
      result = described_class.new(string_type, "some reason")

      expect(result.source).to eq(:unknown)
    end
  end

  describe "#==" do
    it "equals another Result with same attributes" do
      result1 = described_class.new(string_type, "literal", :literal)
      result2 = described_class.new(string_type, "literal", :literal)

      expect(result1).to eq(result2)
    end

    it "does not equal Result with different type" do
      result1 = described_class.new(string_type, "literal", :literal)
      result2 = described_class.new(TypeGuessr::Core::Types::ClassInstance.new("Integer"), "literal", :literal)

      expect(result1).not_to eq(result2)
    end

    it "does not equal Result with different reason" do
      result1 = described_class.new(string_type, "reason1", :literal)
      result2 = described_class.new(string_type, "reason2", :literal)

      expect(result1).not_to eq(result2)
    end

    it "does not equal Result with different source" do
      result1 = described_class.new(string_type, "literal", :literal)
      result2 = described_class.new(string_type, "literal", :project)

      expect(result1).not_to eq(result2)
    end
  end

  describe "#to_s" do
    it "formats result as type (reason)" do
      result = described_class.new(string_type, "literal assignment", :literal)

      expect(result.to_s).to eq("String (literal assignment)")
    end
  end
end
