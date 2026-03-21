# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "location conversion" do
    it "converts Prism location to byte offset integer" do
      source = '"hello"'
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node.loc).to be_a(Integer)
      expect(node.loc).to eq(0)
    end
  end
end
