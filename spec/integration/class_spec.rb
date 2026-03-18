# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# Hover rendering smoke tests — verifies LSP protocol interaction only.
# Full type inference coverage is in spec/inference/class_inference_spec.rb.
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Class Instance Type Inference (Hover Smoke)" do
  include TypeGuessrTestHelper

  context "hover renders type without crash" do
    let(:source) do
      <<~RUBY
        class User
        end

        user = User.new
        user
      RUBY
    end

    it "returns valid hover response" do
      expect_hover_type(line: 5, column: 3, expected: "User")
    end
  end

  context "dynamic class reference returns valid response" do
    let(:source) do
      <<~RUBY
        def foo(klass)
          obj = klass.new
          obj
        end
      RUBY
    end

    it "returns nil or Hover (not crash)" do
      response = hover_on_source(source, { line: 2, character: 2 })
      expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
    end
  end

  context "def node renders Guessed Signature" do
    let(:source) do
      <<~RUBY
        class Calculator
          def self.add(a, b)
            a + b
          end
        end
      RUBY
    end

    it "includes Guessed Signature in hover" do
      response = expect_hover_response(line: 2, column: 12)
      expect(response.contents.value).to include("Guessed Signature")
    end
  end
end
# rubocop:enable RSpec/DescribeClass
