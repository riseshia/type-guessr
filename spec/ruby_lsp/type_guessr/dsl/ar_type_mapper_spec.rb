# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/type_guessr/dsl/ar_type_mapper"

RSpec.describe RubyLsp::TypeGuessr::Dsl::ArTypeMapper do
  describe ".map" do
    def map(...)
      described_class.map(...)
    end

    it "maps string to nullable String" do
      expect(map("string").to_s).to eq("String?")
    end

    it "maps text to nullable String" do
      expect(map("text").to_s).to eq("String?")
    end

    it "maps integer to nullable Integer" do
      expect(map("integer").to_s).to eq("Integer?")
    end

    it "maps bigint to nullable Integer" do
      expect(map("bigint").to_s).to eq("Integer?")
    end

    it "maps boolean to nullable bool (TrueClass | FalseClass | NilClass)" do
      result = map("boolean")
      expect(result).to be_a(TypeGuessr::Core::Types::Union)
      type_names = result.types.map(&:name).sort
      expect(type_names).to eq(%w[FalseClass NilClass TrueClass])
    end

    it "maps float to nullable Float" do
      expect(map("float").to_s).to eq("Float?")
    end

    it "maps decimal to nullable BigDecimal" do
      expect(map("decimal").to_s).to eq("BigDecimal?")
    end

    it "maps date to nullable Date" do
      expect(map("date").to_s).to eq("Date?")
    end

    it "maps datetime to nullable ActiveSupport::TimeWithZone" do
      expect(map("datetime").to_s).to eq("ActiveSupport::TimeWithZone?")
    end

    it "maps timestamp to nullable ActiveSupport::TimeWithZone" do
      expect(map("timestamp").to_s).to eq("ActiveSupport::TimeWithZone?")
    end

    it "maps json to nullable Hash" do
      expect(map("json").to_s).to eq("Hash?")
    end

    it "maps jsonb to nullable Hash" do
      expect(map("jsonb").to_s).to eq("Hash?")
    end

    it "maps unknown type to Unknown" do
      expect(map("binary")).to be_a(TypeGuessr::Core::Types::Unknown)
    end

    it "returns non-nullable when nullable: false" do
      expect(map("string", nullable: false).to_s).to eq("String")
    end

    it "returns non-nullable Integer" do
      expect(map("integer", nullable: false).to_s).to eq("Integer")
    end

    it "returns Unknown for unknown type even with nullable: true" do
      expect(map("blob", nullable: true)).to be_a(TypeGuessr::Core::Types::Unknown)
    end
  end
end
