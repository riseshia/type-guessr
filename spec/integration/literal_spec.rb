# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Literal Type Inference", :doc do
  include TypeGuessrTestHelper

  describe "Basic literals" do
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
          count = 42
          count
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 2, column: 0, expected: "Integer")
      end
    end

    context "Float literal" do
      let(:source) do
        <<~RUBY
          price = 19.99
          price
        RUBY
      end

      it "→ Float" do
        expect_hover_type(line: 2, column: 0, expected: "Float")
      end
    end

    context "Array literal" do
      let(:source) do
        <<~RUBY
          items = []
          items
        RUBY
      end

      it "→ Array" do
        expect_hover_type(line: 2, column: 0, expected: "Array[untyped]")
      end
    end

    context "Hash literal" do
      let(:source) do
        <<~RUBY
          data = {}
          data
        RUBY
      end

      it "→ Hash" do
        expect_hover_type(line: 2, column: 0, expected: "{ }")
      end
    end

    context "Symbol literal" do
      let(:source) do
        <<~RUBY
          status = :active
          status
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 2, column: 0, expected: "Symbol")
      end
    end

    context "TrueClass literal" do
      let(:source) do
        <<~RUBY
          flag = true
          flag
        RUBY
      end

      it "→ true" do
        expect_hover_type(line: 2, column: 0, expected: "true")
      end
    end

    context "FalseClass literal" do
      let(:source) do
        <<~RUBY
          flag = false
          flag
        RUBY
      end

      it "→ false" do
        expect_hover_type(line: 2, column: 0, expected: "false")
      end
    end

    context "NilClass literal" do
      let(:source) do
        <<~RUBY
          value = nil
          value
        RUBY
      end

      it "→ nil" do
        expect_hover_type(line: 2, column: 0, expected: "nil")
      end
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

      it "→ Range[Integer]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[Integer]")
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

      it "→ Range[Integer]" do
        expect_hover_type(line: 4, column: 0, expected: "Range[Integer]")
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
        <<~'RUBY'
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
        <<~'RUBY'
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
