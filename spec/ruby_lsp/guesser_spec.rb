# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/type_guessr/addon"

RSpec.describe RubyLsp::TypeGuessr do
  describe "VERSION" do
    it "has a version number" do
      expect(TypeGuessr::VERSION).not_to be_nil
    end
  end

  describe RubyLsp::TypeGuessr::Addon do
    describe "#name" do
      it "returns TypeGuessr" do
        addon = described_class.new
        expect(addon.name).to eq("TypeGuessr")
      end
    end
  end

  describe RubyLsp::TypeGuessr::Hover do
    it "is defined" do
      expect(defined?(described_class)).to be_truthy
    end
  end
end
