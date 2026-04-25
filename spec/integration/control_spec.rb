# frozen_string_literal: true

require "spec_helper"

# Hover rendering smoke tests — verifies LSP protocol interaction only.
# Full type inference coverage is in spec/inference/control_inference_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Control Flow Type Inference (Hover Smoke)" do
  include TypeGuessrTestHelper

  context "control flow hover" do
    let(:source) do
      <<~RUBY
        def foo(flag)
          x = 1
          if flag
            x = "string"
          end
          x
        end
      RUBY
    end

    it "renders union type in hover response" do
      expect_hover_type(line: 6, column: 2, expected: "Integer | String")
    end
  end

  context "unless statement does not crash" do
    let(:source) do
      <<~RUBY
        def foo(flag)
          x = 1
          unless flag
            x = "string"
          end
          x
        end
      RUBY
    end

    it "returns hover response" do
      expect_hover_response(line: 6, column: 2)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
