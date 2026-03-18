# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# Hover rendering smoke tests — verifies LSP protocol interaction only.
# Full type inference coverage is in spec/inference/variable_inference_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Variable Type Inference (Hover Smoke)" do
  include TypeGuessrTestHelper

  context "instance variable hover" do
    let(:source) do
      <<~RUBY
        class C
          def initialize(x)
            @x = 42
          end

          def foo(_)
            @x
          end
        end
      RUBY
    end

    it "renders type in hover response" do
      expect_hover_type(line: 7, column: 4, expected: "Integer")
    end
  end

  context "block assignment does not crash" do
    let(:source) do
      <<~RUBY
        def baz
          [1, 1.0, "str"]
        end

        def bar
          x = nil
          1.times do |_|
            x, y, z, w = baz
          end
          x
        end
      RUBY
    end

    it "returns non-nil response" do
      response = hover_on_source(source, { line: 9, character: 2 })
      expect(response).not_to be_nil
    end
  end
end
# rubocop:enable RSpec/DescribeClass
