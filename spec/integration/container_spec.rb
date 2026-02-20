# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Container Type Inference", :doc do
  include TypeGuessrTestHelper

  describe "Array type inference" do
    context "Homogeneous integer array" do
      let(:source) do
        <<~RUBY
          nums = [1, 2, 3]
          nums
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer]")
      end
    end

    context "Mixed array with 2 types" do
      let(:source) do
        <<~RUBY
          mixed = [1, "a"]
          mixed
        RUBY
      end

      it "→ [Integer, String]" do
        expect_hover_type(line: 2, column: 0, expected: "[Integer, String]")
      end
    end

    context "Mixed array with 3 types" do
      let(:source) do
        <<~RUBY
          mixed = [1, "a", :sym]
          mixed
        RUBY
      end

      it "→ [Integer, String, Symbol]" do
        expect_hover_type(line: 2, column: 0, expected: "[Integer, String, Symbol]")
      end
    end

    context "Array with 4+ types" do
      let(:source) do
        <<~RUBY
          mixed = [1, "a", :sym, 1.0]
          mixed
        RUBY
      end

      it "→ [Integer, String, Symbol, Float]" do
        expect_hover_type(line: 2, column: 0, expected: "[Integer, String, Symbol, Float]")
      end
    end

    context "Nested array" do
      let(:source) do
        <<~RUBY
          nested = [[1, 2], [3, 4]]
          nested
        RUBY
      end

      it "→ Array[Array[Integer]]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Array[Integer]]")
      end
    end

    context "Deeply nested array" do
      let(:source) do
        <<~RUBY
          deep = [[[1]]]
          deep
        RUBY
      end

      it "→ Array[Array[Array[Integer]]]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Array[Array[Integer]]]")
      end
    end

    context "array with method chaining" do
      let(:source) do
        <<~RUBY
          def foo(a)
            a
          end

          foo([1, 2, 3].to_a)
          r = [1, 2, 3].to_a
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 6, column: 0, expected: "Array[Integer]")
      end
    end
  end

  describe "Hash type inference" do
    context "Symbol-keyed hash" do
      let(:source) do
        <<~RUBY
          user = { name: "John", age: 20 }
          user
        RUBY
      end

      it "→ { name: String, age: Integer }" do
        expect_hover_type(line: 2, column: 0, expected: "{ name: String, age: Integer }")
      end
    end

    context "String-keyed hash" do
      let(:source) do
        <<~RUBY
          data = { "key" => "value" }
          data
        RUBY
      end

      it "→ Hash[String, String]" do
        expect_hover_type(line: 2, column: 0, expected: "Hash[String, String]")
      end
    end

    context "Mixed keys hash" do
      let(:source) do
        <<~RUBY
          mixed = { name: "John", "key" => 1 }
          mixed
        RUBY
      end

      it "→ Hash[String | Symbol, Integer | String]" do
        expect_hover_type(line: 2, column: 0, expected: "Hash[String | Symbol, Integer | String]")
      end
    end

    context "Nested symbol-keyed hash" do
      let(:source) do
        <<~RUBY
          user = { name: "John", address: { city: "Seoul" } }
          user
        RUBY
      end

      it "→ { name: String, address: { city: String } }" do
        expect_hover_type(line: 2, column: 0, expected: "{ name: String, address: { city: String } }")
      end
    end

    context "hash with symbol keys and different value types" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          h = foo
        RUBY
      end

      it "→ { a: Integer, b: String }" do
        expect_hover_type(line: 8, column: 0, expected: "{ a: Integer, b: String }")
      end
    end

    context "hash access with symbol key" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          def bar
            foo[:a]
          end

          r = bar
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 12, column: 0, expected: "Integer")
      end
    end

    context "hash with indexed assignment" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          def baz
            foo[:c] = 1.0
            foo[:c]
          end

          r = baz
        RUBY
      end

      it "→ nil" do
        # NOTE: foo[:c] returns nil because :c key doesn't exist in the original hash
        expect_hover_type(line: 13, column: 0, expected: "nil")
      end
    end

    context "hash with splat operator" do
      let(:source) do
        <<~RUBY
          def bar
            { a: 1 }
          end

          def foo
            { **bar, b: 1 }
          end

          h = foo
        RUBY
      end

      it "→ Hash[Symbol, Integer]" do
        expect_hover_type(line: 9, column: 0, expected: "Hash[Symbol, Integer]")
      end
    end

    context "hash with implicit value syntax" do
      let(:source) do
        <<~RUBY
          def create
            x = 1
            y = "str"
            { x:, y: }
          end

          h = create
        RUBY
      end

      it "→ { x: untyped, y: untyped }" do
        expect_hover_type(line: 7, column: 0, expected: "{ x: untyped, y: untyped }")
      end
    end
  end

  describe "Hash indexed assignment" do
    context "empty hash" do
      let(:source) do
        <<~RUBY
          a = {}
          a[:x] = 1
          a
        RUBY
      end

      it "→ { x: Integer }" do
        expect_hover_type(line: 3, column: 0, expected: "{ x: Integer }")
      end
    end

    context "existing hash" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a[:b] = 3
          a
        RUBY
      end

      it "→ { a: Integer, b: Integer }" do
        expect_hover_type(line: 3, column: 0, expected: "{ a: Integer, b: Integer }")
      end
    end

    context "string key widens to Hash" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a["str_key"] = 2
          a
        RUBY
      end

      it "→ Hash" do
        expect_hover_type(line: 3, column: 0, expected: "Hash[String | Symbol, Integer]")
      end
    end

    context "with string key" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a["f"] = "a"
        RUBY
      end

      it "→ Hash on assignment line" do
        expect_hover_type(line: 2, column: 0, expected: "Hash[String | Symbol, Integer | String]")
      end
    end

    context "with symbol key" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a[:b] = "x"
        RUBY
      end

      it "→ { a: Integer, b: String }" do
        expect_hover_type(line: 2, column: 0, expected: "{ a: Integer, b: String }")
      end
    end
  end

  describe "Hash indexed ||= assignment" do
    context "hash indexed ||= on empty hash" do
      let(:source) do
        <<~RUBY
          def foo
            h = {}
            h[:a] ||= 1
          end

          r = foo
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 6, column: 0, expected: "Integer")
      end
    end
  end

  describe "Array indexed assignment" do
    context "with different type" do
      let(:source) do
        <<~RUBY
          a = [1]
          a[0] = "x"
        RUBY
      end

      it "→ Array[Integer | String]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer | String]")
      end
    end
  end

  describe "Array << operator" do
    context "with different type" do
      let(:source) do
        <<~RUBY
          a = [1]
          a << "x"
        RUBY
      end

      it "→ Array[Integer | String]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer | String]")
      end
    end
  end

  describe "Control flow container mutation" do
    context "Hash field added in if branch" do
      let(:source) do
        <<~RUBY
          def foo(flag)
            h = { a: 1 }
            if flag
              h[:b] = "str"
            end
            h
          end
        RUBY
      end

      it "→ union of branch types (if may not execute)" do
        # Union of both branches: original hash OR hash with added field
        expect_hover_type(line: 6, column: 2, expected: "{ a: Integer } | { a: Integer, b: String }")
      end
    end

    context "Array element added in case branch" do
      let(:source) do
        <<~RUBY
          def foo(n)
            arr = [1]
            case n
            when 1 then arr << "a"
            when 2 then arr << :sym
            end
            arr
          end
        RUBY
      end

      it "→ union of branch array types" do
        # Each case branch produces different array type
        expect_hover_type(line: 7, column: 2, expected: "Array[Integer | String] | Array[Integer | Symbol]")
      end
    end
  end

  describe "Sequential container expansion" do
    context "multiple Hash field additions" do
      let(:source) do
        <<~RUBY
          h = {}
          h[:a] = 1
          h[:b] = "str"
          h[:c] = :sym
          h
        RUBY
      end

      it "→ { a: Integer, b: String, c: Symbol }" do
        expect_hover_type(line: 5, column: 0, expected: "{ a: Integer, b: String, c: Symbol }")
      end
    end

    context "multiple Array element additions" do
      let(:source) do
        <<~RUBY
          arr = []
          arr << 1
          arr << "str"
          arr << :sym
          arr
        RUBY
      end

      it "→ Array[Integer | String | Symbol]" do
        expect_hover_type(line: 5, column: 0, expected: "Array[Integer | String | Symbol]")
      end
    end

    context "mixed Array operations" do
      let(:source) do
        <<~RUBY
          arr = [1]
          arr[0] = "replaced"
          arr << :added
          arr
        RUBY
      end

      it "→ Array[Integer | String | Symbol]" do
        expect_hover_type(line: 4, column: 0, expected: "Array[Integer | String | Symbol]")
      end
    end
  end

  describe "TupleType inference" do
    context "Tuple indexed access with integer literal" do
      let(:source) do
        <<~RUBY
          def foo
            t = [1, "a", :sym]
            t[0]
          end

          r = foo
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 6, column: 0, expected: "Integer")
      end
    end

    context "Tuple indexed access with last element" do
      let(:source) do
        <<~RUBY
          def foo
            t = [1, "a", :sym]
            t[2]
          end

          r = foo
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 6, column: 0, expected: "Symbol")
      end
    end

    context "Tuple negative indexing" do
      let(:source) do
        <<~RUBY
          def foo
            t = [1, "a", :sym]
            t[-1]
          end

          r = foo
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 6, column: 0, expected: "Symbol")
      end
    end

    context "Tuple out of range access" do
      let(:source) do
        <<~RUBY
          def foo
            t = [1, "a"]
            t[5]
          end

          r = foo
        RUBY
      end

      it "→ nil" do
        expect_hover_type(line: 6, column: 0, expected: "nil")
      end
    end

    context "Tuple method falls back to Array RBS" do
      let(:source) do
        <<~RUBY
          t = [1, "a"]
          r = t.size
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 2, column: 0, expected: "Integer")
      end
    end

    context "Homogeneous array stays ArrayType" do
      let(:source) do
        <<~RUBY
          nums = [1, 2, 3]
          nums
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer]")
      end
    end
  end

  describe "Container mutation edge cases" do
    context "container mutation followed by reassignment" do
      let(:source) do
        <<~RUBY
          a = [1, 2]
          a << "str"
          a = { x: 1 }
          a
        RUBY
      end

      it "→ { x: Integer } (not Array)" do
        expect_hover_type(line: 4, column: 0, expected: "{ x: Integer }")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
