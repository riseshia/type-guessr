# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# Hover rendering smoke test — verifies LSP hover returns correct type.
# Full type inference coverage is in spec/inference/literal_inference_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Literal Type Inference (Hover Smoke)" do
  include TypeGuessrTestHelper

  context "basic literal hover" do
    let(:source) do
      <<~RUBY
        name = "John"
        name
      RUBY
    end

    it "renders guessed type in hover response" do
      expect_hover_type(line: 2, column: 0, expected: "String")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
