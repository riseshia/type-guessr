# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLsp::TypeGuessr::HoverContentBuilder do
  subject(:builder) { described_class.new }

  # Type shortcuts
  let(:recipe_type) { TypeGuessr::Core::Types::ClassInstance.new("Recipe") }
  let(:article_type) { TypeGuessr::Core::Types::ClassInstance.new("Article") }
  let(:book_type) { TypeGuessr::Core::Types::ClassInstance.new("Book") }

  before do
    # Disable debug mode for cleaner test assertions
    allow(RubyLsp::TypeGuessr::Config).to receive(:debug?).and_return(false)
  end

  describe "#build" do
    context "when matching_types is empty but method_calls exist" do
      it "returns untyped" do
        type_info = {
          direct_type: nil,
          method_calls: %w[validate save]
        }

        result = builder.build(type_info, matching_types: [], type_entries: {})

        expect(result).to eq("**Guessed type:** untyped")
      end
    end

    context "when matching_types has 4+ results (truncated)" do
      it "returns untyped" do
        type_info = {
          direct_type: nil,
          method_calls: ["common_method"]
        }

        matching_types = [
          recipe_type,
          article_type,
          book_type,
          RubyLsp::TypeGuessr::TypeMatcher::TRUNCATED_MARKER,
        ]

        result = builder.build(type_info, matching_types: matching_types, type_entries: {})

        expect(result).to eq("**Guessed type:** untyped")
      end
    end

    context "when matching_types has 2-3 results" do
      it "returns ambiguous type" do
        type_info = {
          direct_type: nil,
          method_calls: ["author"]
        }

        matching_types = [article_type, book_type]

        result = builder.build(type_info, matching_types: matching_types, type_entries: {})

        expect(result).to eq("**Ambiguous type** (could be: `Article`, `Book`)")
      end
    end

    context "when matching_types has exactly 1 result" do
      it "returns guessed type" do
        type_info = {
          direct_type: nil,
          method_calls: ["ingredients"]
        }

        matching_types = [recipe_type]

        result = builder.build(type_info, matching_types: matching_types, type_entries: {})

        expect(result).to eq("**Guessed type:** `Recipe`")
      end
    end

    context "when no method_calls and no matching_types" do
      it "returns nil" do
        type_info = {
          direct_type: nil,
          method_calls: []
        }

        result = builder.build(type_info, matching_types: [], type_entries: {})

        expect(result).to be_nil
      end
    end
  end
end
