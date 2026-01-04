# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "IR-based Hover", :doc do
  include TypeGuessrTestHelper

  def hover_on_source(source, position)
    with_server_and_addon(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position }
      )

      result = pop_result(server)
      result.response
    end
  end

  describe "Literal Type Inference" do
    context "String literal" do
      let(:source) do
        <<~RUBY
          name = "John"
          name
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 2, column: 0, expected: "String")
      end
    end

    context "Integer literal" do
      let(:source) do
        <<~RUBY
          age = 42
          age
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 2, column: 0, expected: "Integer")
      end
    end

    context "Array literal" do
      let(:source) do
        <<~RUBY
          items = [1, 2, 3]
          items
        RUBY
      end

      it "→ Array" do
        expect_hover_type(line: 2, column: 0, expected: "Array")
      end
    end
  end

  describe "Method Call Type Inference" do
    context "String#upcase" do
      let(:source) do
        <<~RUBY
          name = "hello"
          result = name.upcase
          result
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 3, column: 0, expected: "String")
      end
    end
  end

  describe "Variable Assignment" do
    context "Simple assignment" do
      let(:source) do
        <<~RUBY
          x = "test"
          x
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 2, column: 0, expected: "String")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
