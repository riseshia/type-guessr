# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Control Flow Type Inference" do
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

  describe "If-else branches" do
    context "ternary operator with different types" do
      let(:source) do
        <<~RUBY
          def foo(n)
            n ? 1 : "str"
          end
          r = foo(true)
        RUBY
      end

      it "infers union type Integer | String" do
        expect_hover_type(line: 4, column: 0, expected: "Integer | String")
      end
    end

    context "if modifier with assignment" do
      let(:source) do
        <<~RUBY
          def bar(n)
            n = 1 if n
            n
          end
          r = bar(true)
        RUBY
      end

      it "infers n as untyped (parameter type unknown, merge with Integer)" do
        expect_hover_type(line: 5, column: 0, expected: "untyped")
      end
    end

    context "unless modifier with assignment" do
      let(:source) do
        <<~RUBY
          def baz(n)
            n = 1 unless n
          end
          r = baz(nil)
        RUBY
      end

      it "infers result as Integer | nil" do
        expect_hover_type(line: 4, column: 0, expected: "?Integer")
      end
    end

    context "if-else with symbol literals" do
      let(:source) do
        <<~RUBY
          def foo
            if true
              :ok
            else
              :fail
            end
          end
          r = foo
        RUBY
      end

      it "infers union of :ok | :fail" do
        expect_hover_type(line: 8, column: 0, expected: "Symbol")
      end
    end
  end

  describe "Case expressions" do
    context "case with all branches returning different types" do
      let(:source) do
        <<~RUBY
          def foo(n)
            case n
            when 1
              1
            when 2
              "str"
            else
              1.0
            end
          end
          r = foo(1)
        RUBY
      end

      it "infers union type Float | Integer | String" do
        expect_hover_type(line: 11, column: 0, expected: "Float | Integer | String")
      end
    end

    context "case without else clause" do
      let(:source) do
        <<~RUBY
          def bar(n)
            case n
            when 1
              1
            when 2
              "str"
            end
          end
          r = bar(1)
        RUBY
      end

      it "infers union type including nil" do
        response = hover_on_source(source, { line: 8, character: 0 })
        expect(response).not_to be_nil
        # Should be Integer | String | nil
      end
    end

    context "case with raise in else clause" do
      let(:source) do
        <<~RUBY
          def baz(n)
            case n
            when 1
              1
            when 2
              "str"
            else
              raise
            end
          end
          r = baz(1)
        RUBY
      end

      it "infers union type Integer | String (raise doesn't contribute)" do
        expect_hover_type(line: 11, column: 0, expected: "Integer | String")
      end
    end

    context "case with all empty branches" do
      let(:source) do
        <<~RUBY
          def qux(n)
            case n
            when 1
            when 2
            else
            end
          end
          r = qux(1)
        RUBY
      end

      it "infers nil" do
        expect_hover_type(line: 8, column: 0, expected: "nil")
      end
    end

    context "case without predicate" do
      let(:source) do
        <<~RUBY
          def without_predicate(n)
            case
            when true
              1
            end
          end
          r = without_predicate(nil)
        RUBY
      end

      it "infers Integer | nil" do
        expect_hover_type(line: 7, column: 0, expected: "?Integer")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
