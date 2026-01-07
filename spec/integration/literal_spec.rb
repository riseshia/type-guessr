# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Literal Type Inference from TypeProf Scenarios" do
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

  describe "Range literals" do
    context "inclusive range (0..1)" do
      let(:source) do
        <<~RUBY
          def foo
            0..1
          end
          r = foo
        RUBY
      end

      it "→ Range[Integer]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[Integer]")
      end
    end

    context "endless range (0..)" do
      let(:source) do
        <<~RUBY
          def bar
            0..
          end
          r = bar
        RUBY
      end

      it "→ Range[Integer | nil]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[Integer | nil]")
      end
    end

    context "beginless range (..1)" do
      let(:source) do
        <<~RUBY
          def baz
            ..1
          end
          r = baz
        RUBY
      end

      it "→ Range[Integer | nil]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[Integer | nil]")
      end
    end

    context "nil range (nil..nil)" do
      let(:source) do
        <<~RUBY
          def qux
            nil..nil
          end
          r = qux
        RUBY
      end

      it "→ Range[nil]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[nil]")
      end
    end
  end

  describe "Complex number literal" do
    context "imaginary number (1i)" do
      let(:source) do
        <<~RUBY
          def check
            1i
          end
          c = check
        RUBY
      end

      it "→ Complex" do
        expect_hover_type(line: 4, column: 0, expected: "Complex")
      end
    end
  end

  describe "Rational number literal" do
    context "rational number (1r)" do
      let(:source) do
        <<~RUBY
          def check
            1r
          end
          r = check
        RUBY
      end

      it "→ Rational" do
        expect_hover_type(line: 4, column: 0, expected: "Rational")
      end
    end
  end

  describe "Regexp literal" do
    context "simple regexp (/foo/)" do
      let(:source) do
        <<~RUBY
          def check1
            /foo/
          end
          r = check1
        RUBY
      end

      it "→ Regexp" do
        expect_hover_type(line: 4, column: 0, expected: "Regexp")
      end
    end

    context "regexp with interpolation" do
      let(:source) do
        <<~RUBY
          def check2
            /foo1bar/
          end
          r = check2
        RUBY
      end

      it "→ Regexp" do
        expect_hover_type(line: 4, column: 0, expected: "Regexp")
      end
    end
  end

  describe "Interpolated strings" do
    context "string with interpolation" do
      let(:source) do
        <<~RUBY
          def bar(n)
            "bar"
          end

          def foo
            "foo#{bar(1)}"
          end

          s = foo
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 9, column: 0, expected: "String")
      end
    end

    context "string with empty interpolation" do
      let(:source) do
        <<~RUBY
          def foo
            "foo"
          end
          s = foo
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 4, column: 0, expected: "String")
      end
    end

    context "backtick string (xstring)" do
      let(:source) do
        <<~RUBY
          def xstring_lit(n)
            `echo foo`
          end
          s = xstring_lit(10)
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 4, column: 0, expected: "String")
      end
    end

    context "string with global variable interpolation" do
      let(:source) do
        <<~RUBY
          def foo
            "#{Regexp.last_match(1)}"
          end
          s = foo
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 4, column: 0, expected: "String")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
