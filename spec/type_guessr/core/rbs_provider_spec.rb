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
end
