# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Control Flow Type Inference", :doc do
  include TypeGuessrTestHelper

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

      it "→ Integer | String" do
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

      it "→ untyped" do
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

      it "→ ?Integer" do
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

      it "→ Symbol" do
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

      it "→ Float | Integer | String" do
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

      it "→ ?Integer | String" do
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

      it "→ Integer | String" do
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

      it "→ nil" do
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

      it "→ ?Integer" do
        expect_hover_type(line: 7, column: 0, expected: "?Integer")
      end
    end
  end

  describe "Variable reassignment in control flow" do
    context "Conditional reassignment" do
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

      it "→ Integer | String" do
        expect_hover_type(line: 6, column: 2, expected: "Integer | String")
      end
    end

    context "Type within branch" do
      let(:source) do
        <<~RUBY
          def foo(flag)
            x = 1
            if flag
              x = "string"
              x
            end
          end
        RUBY
      end

      it "→ String (within branch)" do
        expect_hover_type(line: 5, column: 4, expected: "String")
        expect_hover_type_excludes(line: 5, column: 4, types: ["Integer"])
      end
    end

    context "Simple reassignment" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1
            x = "string"
            x
          end
        RUBY
      end

      it "→ String (after reassignment)" do
        expect_hover_type(line: 4, column: 2, expected: "String")
        expect_hover_type_excludes(line: 4, column: 2, types: ["Integer"])
      end
    end

    context "reassignment in non-first-line method" do
      let(:source) do
        <<~RUBY
          class MyClass
            def some_other_method
              # filler
            end

            def foo
              x = 1
              x = "string"
              x
            end
          end
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 9, column: 4, expected: "String")
        expect_hover_type_excludes(line: 9, column: 4, types: ["Integer"])
      end
    end

    context "reassignment at top-level (read node)" do
      let(:source) do
        <<~RUBY
          a = [1,2,3]
          a = { a: 1, b: 2 }
          a
        RUBY
      end

      it "→ Hash (not Array)" do
        expect_hover_response(line: 3, column: 0)
        expect_hover_type_excludes(line: 3, column: 0, types: ["Array"])
      end
    end

    context "reassignment at top-level (write node)" do
      let(:source) do
        <<~RUBY
          a = [1,2,3]
          a = { a: 1, b: 2 }
        RUBY
      end

      it "→ Hash (not Array)" do
        expect_hover_response(line: 2, column: 0)
        expect_hover_type_excludes(line: 2, column: 0, types: ["Array"])
      end
    end

    context "reassignment with method calls" do
      let(:source) do
        <<~RUBY
          a = [1,2,3]
          b = a.map do |num|
            num * 2
          end
          a = { a: 1, b: 2 }
        RUBY
      end

      it "→ Hash (not Array)" do
        expect_hover_response(line: 5, column: 0)
        expect_hover_type_excludes(line: 5, column: 0, types: ["Array"])
      end
    end

    context "instance variable fallback" do
      let(:source) do
        <<~RUBY
          class Foo
            def bar
              @instance_var = "test"
              @instance_var
            end
          end
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 4, column: 4, expected: "String")
      end
    end

    context "elsif branches" do
      let(:source) do
        <<~RUBY
          def foo(flag)
            x = 1
            if flag == 1
              x = "string"
            elsif flag == 2
              x = :symbol
            end
            x
          end
        RUBY
      end

      it "→ Integer | String | Symbol" do
        expect_hover_type(line: 8, column: 2, expected: "Integer | String | Symbol")
      end
    end

    context "unless statement" do
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

      it "→ Integer | String" do
        expect_hover_response(line: 6, column: 2)
      end
    end

    context "||= compound assignment with nil lhs" do
      let(:source) do
        <<~RUBY
          def foo
            x = nil
            x ||= 1
            x
          end
        RUBY
      end

      it "→ Integer (nil filtered by truthiness)" do
        expect_hover_type(line: 4, column: 2, expected: "Integer")
      end
    end

    context "||= compound assignment with truthy lhs" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1
            x ||= "hello"
            x
          end
        RUBY
      end

      it "→ Integer (truthy lhs, rhs unreachable)" do
        expect_hover_type(line: 4, column: 2, expected: "Integer")
      end
    end

    context "hash access with || fallback (variable key)" do
      let(:source) do
        <<~RUBY
          def foo(key)
            h = {}
            keys = h[key] || []
            keys
          end
        RUBY
      end

      it "→ [] (RHS used when LHS is unknown)" do
        expect_hover_type(line: 4, column: 2, expected: "[]")
      end
    end

    context "&&= compound assignment" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1
            x &&= "string"
            x
          end
        RUBY
      end

      it "→ Integer | String" do
        expect_hover_type(line: 4, column: 2, expected: "Integer | String")
      end
    end

    context "+= compound assignment" do
      let(:source) do
        <<~RUBY
          def foo
            x = "hello"
            x += " world"
            x
          end
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 4, column: 2, expected: "String")
      end
    end

    context "guard clause with return" do
      let(:source) do
        <<~RUBY
          def foo(x)
            return unless x
            y = 1
            y
          end
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 4, column: 2, expected: "Integer")
      end
    end
  end

  describe "Guard Clause Type Narrowing" do
    context "return unless local_var narrows type" do
      let(:source) do
        <<~RUBY
          def foo(x)
            x = nil
            x = "hello" if true
            return unless x
            x
          end
        RUBY
      end

      it "→ String (NilClass removed after guard)" do
        expect_hover_type(line: 5, column: 2, expected: "String")
        expect_hover_type_excludes(line: 5, column: 2, types: ["NilClass"])
      end
    end

    context "return nil unless @ivar narrows instance variable" do
      let(:source) do
        <<~RUBY
          class Foo
            def initialize(flag)
              @data = if flag
                        [1, 2, 3]
                      else
                        nil
                      end
            end

            def process
              return nil unless @data
              @data
            end
          end
        RUBY
      end

      it "→ [Integer, Integer, Integer] (NilClass removed after guard)" do
        expect_hover_type(line: 12, column: 4, expected: "[Integer, Integer, Integer]")
      end
    end

    context "raise unless local_var narrows type" do
      let(:source) do
        <<~RUBY
          def bar(x)
            x = nil
            x = 42 if true
            raise "error" unless x
            x
          end
        RUBY
      end

      it "→ Integer (NilClass removed after guard)" do
        expect_hover_type(line: 5, column: 2, expected: "Integer")
        expect_hover_type_excludes(line: 5, column: 2, types: ["NilClass"])
      end
    end
  end

  describe "Explicit Return Handling" do
    context "early return with guard clause" do
      let(:source) do
        <<~RUBY
          class Test
            def flip(flag = true)
              return false if flag
              flag
            end
          end
        RUBY
      end

      it "→ (?true flag) -> bool" do
        expect_hover_method_signature(line: 2, column: 6, expected_signature: "(?true flag) -> bool")
      end
    end

    context "multiple explicit returns" do
      let(:source) do
        <<~RUBY
          class Test
            def classify(n)
              return "negative" if n < 0
              return "zero" if n == 0
              "positive"
            end
          end
        RUBY
      end

      it "→ (untyped n) -> String" do
        expect_hover_method_signature(line: 2, column: 6, expected_signature: "(untyped n) -> String")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
