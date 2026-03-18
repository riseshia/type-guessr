# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# Hover rendering smoke test — verifies LSP hover returns correct type.
# Full type inference coverage is in spec/inference/container_inference_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Container Type Inference (Hover Smoke)" do
  include TypeGuessrTestHelper

  context "array hover" do
    let(:source) do
      <<~RUBY
        nums = [1, 2, 3]
        nums
      RUBY
    end

    it "renders tuple type in hover response" do
      expect_hover_type(line: 2, column: 0, expected: "[Integer, Integer, Integer]")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
