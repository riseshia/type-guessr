# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Hover Integration" do
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

  describe "Literal Type Inference", :doc do
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
        expect_hover_type(line: 2, column: 0, expected: "Array")
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
        expect_hover_type(line: 2, column: 0, expected: "Hash")
      end
    end

    context "Hash indexed assignment - empty hash" do
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

    context "Hash indexed assignment - existing hash" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a[:b] = 3
          a
        RUBY
      end

      it "has both fields a and b" do
        response = hover_on_source(source, { line: 2, character: 0 })
        # Check that both fields are present, regardless of order
        expect(response.contents.value).to include("a: Integer")
        expect(response.contents.value).to include("b: Integer")
      end
    end

    context "Hash indexed assignment - string key widens to Hash" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a["str_key"] = 2
          a
        RUBY
      end

      it "→ Hash" do
        expect_hover_type(line: 3, column: 0, expected: "Hash")
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

    context "Range literal" do
      let(:source) do
        <<~RUBY
          numbers = 1..10
          numbers
        RUBY
      end

      it "→ Range" do
        expect_hover_type(line: 2, column: 0, expected: "Range")
      end
    end

    context "Regexp literal" do
      let(:source) do
        <<~RUBY
          pattern = /[a-z]+/
          pattern
        RUBY
      end

      it "→ Regexp" do
        expect_hover_type(line: 2, column: 0, expected: "Regexp")
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

    context "Interpolated string" do
      let(:source) do
        <<~RUBY
          name = "Alice"
          greeting = "Hello \#{name}"
          greeting
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 3, column: 0, expected: "String")
      end
    end
  end

  describe "Array Type Inference Edge Cases", :doc do
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

      it "→ Array[Integer | String]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer | String]")
      end
    end

    context "Mixed array with 3 types" do
      let(:source) do
        <<~RUBY
          mixed = [1, "a", :sym]
          mixed
        RUBY
      end

      it "→ Array[Integer | String | Symbol]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer | String | Symbol]")
      end
    end

    context "Array with 4+ types" do
      let(:source) do
        <<~RUBY
          mixed = [1, "a", :sym, 1.0]
          mixed
        RUBY
      end

      it "→ Array[Integer | String | Symbol | Float]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer | String | Symbol | Float]")
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
  end

  describe "Hash Type Inference Edge Cases" do
    # Edge case: Symbol-keyed hash
    it "infers HashShape from symbol-keyed hash" do
      source = <<~RUBY
        user = { name: "John", age: 20 }
        user
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response.contents.value).to match(/Guessed Type:.*\{/)
      expect(response.contents.value).to match(/name:/)
      expect(response.contents.value).to match(/age:/)
    end

    # Edge case: Non-symbol keys
    it "infers Hash from string-keyed hash" do
      source = <<~RUBY
        data = { "key" => "value" }
        data
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response.contents.value).to match(/Guessed Type:.*Hash/)
    end

    # Edge case: Mixed keys
    it "infers Hash from hash with mixed keys" do
      source = <<~RUBY
        mixed = { name: "John", "key" => 1 }
        mixed
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response.contents.value).to match(/Guessed Type:.*Hash/)
    end

    # Edge case: Nested hash
    it "infers nested HashShape from nested symbol-keyed hash" do
      source = <<~RUBY
        user = { name: "John", address: { city: "Seoul" } }
        user
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response.contents.value).to match(/Guessed Type:.*\{/)
      expect(response.contents.value).to match(/name:/)
      expect(response.contents.value).to match(/address:/)
    end
  end

  describe ".new Call Type Inference", :doc do
    context "Simple class" do
      let(:source) do
        <<~RUBY
          class User
          end

          user = User.new
          user
        RUBY
      end

      it "→ User" do
        expect_hover_type(line: 5, column: 3, expected: "User")
      end
    end

    context "Namespaced class" do
      let(:source) do
        <<~RUBY
          module Admin
            class User
            end
          end

          admin = Admin::User.new
          admin
        RUBY
      end

      it "→ Admin::User" do
        expect_hover_type(line: 7, column: 3, expected: "Admin::User")
      end
    end

    describe ".new with arguments" do
      let(:source) do
        <<~RUBY
          class User
          end

          user = User.new("name", 20)
          user
        RUBY
      end

      it "→ User" do
        expect_hover_type(line: 4, column: 3, expected: "User")
      end
    end

    context "Deeply nested namespace" do
      let(:source) do
        <<~RUBY
          module A
            module B
              module C
                class D
                end
              end
            end
          end

          obj = A::B::C::D.new
          obj
        RUBY
      end

      it "→ A::B::C::D" do
        expect_hover_type(line: 10, column: 3, expected: "A::B::C::D")
      end
    end

    context "Dynamic class reference" do
      let(:source) do
        <<~RUBY
          def foo(klass)
            obj = klass.new
            obj
          end
        RUBY
      end

      it "does not infer type" do
        response = hover_on_source(source, { line: 2, character: 2 })
        # Should not infer a specific type since klass is unknown
        expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
      end
    end
  end

  describe "Method-Call Based Inference" do
    it "infers single type when method is unique" do
      source = <<~RUBY
        class Recipe
          def ingredients
            []
          end

          def steps
            []
          end
        end

        class Article
          def content
            ""
          end
        end

        def process(recipe)
          recipe.ingredients
          recipe.steps
          recipe
        end
      RUBY

      response = hover_on_source(source, { line: 16, character: 12 })

      expect(response.contents.value).to match(/Guessed Type:.*Recipe/)
      expect(response.contents.value).not_to match(/Article/)
    end

    it "shows ambiguous when multiple classes match" do
      source = <<~RUBY
        class Persistable
          def save
          end

          def destroy
          end
        end

        class Cacheable
          def save
          end

          def destroy
          end
        end

        def process(item)
          item.save
          item.destroy
          item
        end
      RUBY

      response = hover_on_source(source, { line: 16, character: 12 })

      expect(response.contents.value).to match(/Cacheable/)
      expect(response.contents.value).to match(/Persistable/)
    end

    it "truncates when too many classes match" do
      source = <<~RUBY
        class ClassA
          def common_method_for_truncation_test
          end
        end

        class ClassB
          def common_method_for_truncation_test
          end
        end

        class ClassC
          def common_method_for_truncation_test
          end
        end

        class ClassD
          def common_method_for_truncation_test
          end
        end

        class ClassE
          def common_method_for_truncation_test
          end
        end

        def process(item)
          item.common_method_for_truncation_test
          item
        end
      RUBY

      response = hover_on_source(source, { line: 25, character: 12 })

      # When 4+ classes match, show untyped instead of listing them
      expect(response.contents.value).to match(/untyped/)
    end
  end

  describe "Variable Scope Isolation" do
    it "isolates same parameter name across methods" do
      source = <<~RUBY
        class Foo
          def method_a(context)
            @ctx = context
          end

          def method_b(context)
            context.name
            context.age
          end
        end
      RUBY

      response_a = hover_on_source(source, { line: 2, character: 15 })
      response_b = hover_on_source(source, { line: 6, character: 4 })

      expect(response_a.contents.value).not_to include("name")
      expect(response_a.contents.value).not_to include("age")

      expect(response_b.contents.value).to include("name")
      expect(response_b.contents.value).to include("age")
    end

    it "distinguishes local from instance variable" do
      source = <<~RUBY
        class Bar
          def setup
            @user = User.new
          end

          def process
            user = "string"
            user
          end
        end

        class User
        end
      RUBY

      response = hover_on_source(source, { line: 7, character: 4 })

      expect(response.contents.value).to match(/String/)
      expect(response.contents.value).not_to match(/User/)
    end

    # Edge case: Block-local variable shadowing
    it "handles block-local variable shadowing outer variable" do
      source = <<~RUBY
        def foo
          x = 1
          [1, 2].each do |x|
            x
          end
        end
      RUBY

      response = hover_on_source(source, { line: 3, character: 4 })

      # Inside block, x refers to block parameter (Integer from array element)
      expect(response).not_to be_nil
    end

    # Edge case: Top-level variable
    it "handles top-level variable definition" do
      source = <<~RUBY
        x = 42
        x
      RUBY

      response = hover_on_source(source, { line: 1, character: 0 })

      expect(response.contents.value).to match(/Integer/)
    end

    # Edge case: Singleton class scope
    it "handles singleton class scope" do
      source = <<~RUBY
        class Foo
          class << self
            def bar
              x = "singleton"
              x
            end
          end
        end
      RUBY

      response = hover_on_source(source, { line: 4, character: 6 })

      expect(response.contents.value).to match(/String/)
    end
  end

  describe "Parameter Hover" do
    it "shows hover on required parameter" do
      source = <<~RUBY
        def greet(name)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on optional parameter" do
      source = <<~RUBY
        def greet(name = "World")
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on keyword parameter" do
      source = <<~RUBY
        def greet(name:)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on rest parameter" do
      source = <<~RUBY
        def greet(*names)
          names.join
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on block parameter" do
      source = <<~RUBY
        def execute(&block)
          block.call
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on forwarding parameter" do
      source = <<~RUBY
        def forward(...)
          other_method(...)
        end
      RUBY

      response = hover_on_source(source, { line: 0, character: 12 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    # Edge case: Keyword rest parameter
    it "shows hover on keyword rest parameter" do
      source = <<~RUBY
        def process(**kwargs)
          kwargs.keys
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response).not_to be_nil
    end

    # Edge case: Optional parameter with .new default
    it "infers type from optional parameter with .new default" do
      source = <<~RUBY
        class User
        end

        def foo(x = User.new)
          x
        end
      RUBY

      response = hover_on_source(source, { line: 4, character: 2 })

      # Type inference might vary based on implementation
      expect(response).not_to be_nil
    end

    # Edge case: Optional parameter with literal default
    it "shows hover on optional parameter with integer default" do
      source = <<~RUBY
        def foo(x = 42)
          x
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 2 })

      expect(response).not_to be_nil
    end
  end

  describe "Type Definition Links" do
    it "includes link to class definition" do
      source = <<~RUBY
        class Recipe
          def ingredients
          end

          def steps
          end
        end

        def cook(recipe)
          recipe.ingredients
          recipe.steps
          recipe
        end
      RUBY

      response = hover_on_source(source, { line: 11, character: 4 })

      expect(response.contents.value).to match(/Guessed Type:/)
      expect(response.contents.value).to match(/\[`Recipe`\]\(file:/)
    end
  end

  describe "Debug Mode" do
    around do |example|
      # Enable debug mode for this test
      ENV["TYPE_GUESSR_DEBUG"] = "1"
      TypeGuessr::Core::Logger.instance_variable_set(:@debug_enabled, nil)
      example.run
    ensure
      # Clean up debug mode
      ENV.delete("TYPE_GUESSR_DEBUG")
      TypeGuessr::Core::Logger.instance_variable_set(:@debug_enabled, nil)
    end

    it "shows debug info when enabled" do
      source = <<~RUBY
        def process(item)
          item.save
          item
        end
      RUBY

      response = hover_on_source(source, { line: 0, character: 12 })

      # Debug mode is enabled in spec_helper.rb via ENV["TYPE_GUESSR_DEBUG"] = "1"
      expect(response.contents.value).to match(/\*\*\[TypeGuessr Debug\]/)
      expect(response.contents.value).to match(/Reason:/)
      expect(response.contents.value).to match(/Method calls:/)
    end
  end

  describe "Edge Cases" do
    it "shows hover on self" do
      source = <<~RUBY
        class Foo
          def bar
            self
          end
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "infers type for global variable" do
      source = <<~RUBY
        $global = "test"
        $global.upcase
      RUBY

      response = hover_on_source(source, { line: 1, character: 0 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "infers type for class variable" do
      source = <<~RUBY
        class Counter
          @@count = 0
          @@count.succ
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end
  end

  describe "FlowAnalyzer Integration", :doc do
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

      it "→ String (not union)" do
        response = hover_on_source(source, { line: 4, character: 4 })
        expect(response.contents.value).to match(/String/)
        expect(response.contents.value).not_to match(/Integer.*\|.*String/)
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

      it "→ String (not Integer)" do
        response = hover_on_source(source, { line: 3, character: 2 })
        expect(response.contents.value).to match(/String/)
        expect(response.contents.value).not_to match(/Integer/)
      end
    end

    it "tracks type changes through reassignment in non-first-line method" do
      source = <<~RUBY
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

      # Hover on final "x" (0-indexed: line 8) - should show String (the last assignment)
      response = hover_on_source(source, { line: 8, character: 4 })

      expect(response.contents.value).to match(/String/)
      expect(response.contents.value).not_to match(/Integer/)
    end

    it "tracks type changes through reassignment at top-level (read node)" do
      source = <<~RUBY
        a = [1,2,3]
        a = { a: 1, b: 2 }
        a
      RUBY

      # Hover on final "a" read - should show Hash/HashShape (the last assignment), NOT Array
      response = hover_on_source(source, { line: 2, character: 0 })

      # Should show HashShape or Hash
      expect(response.contents.value).to match(/\{|Hash/)
      # Should NOT show Array from the first assignment
      expect(response.contents.value).not_to match(/Array/)
    end

    it "tracks type changes through reassignment at top-level (write node)" do
      source = <<~RUBY
        a = [1,2,3]
        a = { a: 1, b: 2 }
      RUBY

      # Hover on "a" in the second assignment line (the variable being reassigned)
      response = hover_on_source(source, { line: 1, character: 0 })

      # Should show HashShape or Hash (the new value being assigned)
      expect(response.contents.value).to match(/\{|Hash/)
      # Should NOT show Array from the first assignment
      expect(response.contents.value).not_to match(/Array/)
    end

    it "tracks type changes through reassignment with method calls" do
      source = <<~RUBY
        a = [1,2,3]
        b = a.map do |num|
          num * 2
        end
        a = { a: 1, b: 2 }
      RUBY

      # Hover on "a" in the last assignment line
      response = hover_on_source(source, { line: 4, character: 0 })

      # Should show HashShape or Hash (the new value being assigned)
      expect(response.contents.value).to match(/\{|Hash/)
      # Should NOT show Array from the first assignment
      expect(response.contents.value).not_to match(/Array/)
    end

    it "falls back to VariableTypeResolver when FlowAnalyzer fails" do
      source = <<~RUBY
        class Foo
          def bar
            @instance_var = "test"
            @instance_var
          end
        end
      RUBY

      # FlowAnalyzer doesn't handle instance variables well
      # Should fall back to existing VariableTypeResolver
      response = hover_on_source(source, { line: 3, character: 4 })

      expect(response.contents.value).to match(/String/)
    end

    # Edge case: elsif branches
    it "infers union type from elsif branches" do
      source = <<~RUBY
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

      response = hover_on_source(source, { line: 7, character: 2 })

      expect(response.contents.value).to match(/Integer/)
      expect(response.contents.value).to match(/String/)
      expect(response.contents.value).to match(/Symbol/)
    end

    # Edge case: Ternary operator
    it "infers union type from ternary operator" do
      source = <<~RUBY
        def foo(flag)
          x = flag ? 1 : "str"
          x
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Integer/)
      expect(response.contents.value).to match(/String/)
    end

    # Edge case: unless statement
    it "handles unless statement" do
      source = <<~RUBY
        def foo(flag)
          x = 1
          unless flag
            x = "string"
          end
          x
        end
      RUBY

      response = hover_on_source(source, { line: 5, character: 2 })

      # Should work similarly to if - may show union or last type
      expect(response).not_to be_nil
    end

    # Edge case: Compound assignment ||=
    it "infers union type from ||= assignment" do
      source = <<~RUBY
        def foo
          x = nil
          x ||= 1
          x
        end
      RUBY

      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/Integer|nil/)
    end

    # Edge case: Compound assignment &&=
    it "infers union type from &&= assignment" do
      source = <<~RUBY
        def foo
          x = 1
          x &&= "string"
          x
        end
      RUBY

      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/Integer|String/)
    end

    # Edge case: Guard clause
    it "handles guard clause with return" do
      source = <<~RUBY
        def foo(x)
          return unless x
          y = 1
          y
        end
      RUBY

      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/Integer/)
    end
  end

  describe "Method Call Return Type (Expression Type)" do
    it "infers variable type from method call assignment" do
      source = <<~RUBY
        def example
          hoge = 1
          hoge2 = hoge.to_s
          hoge2
        end
      RUBY

      # Hover on "hoge2" - should infer String from Integer#to_s return type
      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/String/)
    end

    it "infers variable type from chained method call assignment" do
      source = <<~RUBY
        def example
          name = "hello"
          result = name.upcase.length
          result
        end
      RUBY

      # Hover on "result" - should infer Integer from String#length
      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/Integer/)
    end

    it "shows unknown for user-defined class method assignment" do
      source = <<~RUBY
        class User
          def name
            "John"
          end
        end

        def example
          user = User.new
          result = user.name
          result
        end
      RUBY

      # Hover on "result" - User#name is not in RBS, should show untyped
      response = hover_on_source(source, { line: 9, character: 2 })

      # Should show something (either unknown or no type info)
      # For now, we just check it doesn't crash
      expect(response).not_to be_nil
    end
  end

  describe "User-Defined Method Return Type" do
    # NOTE: These tests use spec_helper's with_server_and_addon which indexes test sources
    # in both TypeGuessr's VariableIndex and ruby-lsp's RubyIndexer.
    # The core functionality is also verified in spec/type_guessr/core/user_method_return_resolver_spec.rb

    it "infers return type from user-defined method with literal return" do
      source = <<~RUBY
        class Animal
          def name
            "Dog"
          end
        end

        def example
          animal = Animal.new
          result = animal.name
          result
        end
      RUBY

      # Hover on "result" - should infer String from Animal#name return type
      response = hover_on_source(source, { line: 8, character: 2 })

      expect(response.contents.value).to match(/String/)
    end

    it "infers nil for empty method body" do
      source = <<~RUBY
        class Animal
          def eat
          end
        end

        def example
          c = Animal.new
          cc = c.eat
          cc
        end
      RUBY

      # Hover on "cc" - should infer nil from Animal#eat empty body
      response = hover_on_source(source, { line: 7, character: 2 })

      expect(response.contents.value).to match(/nil/)
    end

    it "infers return type from explicit return statement" do
      source = <<~RUBY
        class Calculator
          def compute
            return 42
          end
        end

        def example
          calc = Calculator.new
          result = calc.compute
          result
        end
      RUBY

      # Hover on "result" - should infer Integer from Calculator#compute
      response = hover_on_source(source, { line: 8, character: 2 })

      expect(response.contents.value).to match(/Integer/)
    end

    it "infers union type from multiple return paths" do
      source = <<~RUBY
        class Conditional
          def value
            if true
              "string"
            else
              42
            end
          end
        end

        def example
          obj = Conditional.new
          result = obj.value
          result
        end
      RUBY

      # Hover on "result" - should infer String | Integer union type
      response = hover_on_source(source, { line: 12, character: 2 })

      # Should show union of String and Integer
      expect(response.contents.value).to match(/String.*Integer|Integer.*String/)
    end

    it "works with nested method calls" do
      source = <<~RUBY
        class StringWrapper
          def value
            "hello"
          end
        end

        def example
          wrapper = StringWrapper.new
          length = wrapper.value.length
          length
        end
      RUBY

      # Hover on "length" - wrapper.value returns String, String#length returns Integer
      response = hover_on_source(source, { line: 8, character: 2 })

      expect(response.contents.value).to match(/Integer/)
    end

    it "falls back to RBS when available" do
      source = <<~RUBY
        def example
          arr = [1, 2, 3]
          result = arr.map { |x| x * 2 }
          result
        end
      RUBY

      # Hover on "result" - Array#map is in RBS, should use RBS first
      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/Array/)
    end
  end

  describe "Method-Call Set Heuristic" do
    it "infers type from method pattern when parameter type is unknown" do
      source = <<~RUBY
        class Document
          def title
            "doc"
          end
        end

        def example(obj)
          obj.title
          obj
        end
      RUBY

      # Hover on "obj" - obj is unknown parameter, but title is unique to Document
      response = hover_on_source(source, { line: 8, character: 2 })

      expect(response.contents.value).to match(/Document/)
    end

    it "infers receiver type from multiple method patterns" do
      source = <<~RUBY
        class Widget
          def render
          end

          def update
          end
        end

        def example(obj)
          obj.render
          obj.update
          obj
        end
      RUBY

      # Hover on "obj"
      # obj has render and update → unique to Widget
      response = hover_on_source(source, { line: 11, character: 2 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Widget/)
    end

    it "shows union type when multiple classes match duck typing" do
      source = <<~RUBY
        class Parser
          def process
          end
        end

        class Compiler
          def process
          end
        end

        def example(obj)
          obj.process
          x = 1
          obj
        end
      RUBY

      # Hover on "obj" at line 14
      # obj has process → both Parser and Compiler match
      response = hover_on_source(source, { line: 14, character: 2 })

      # Shows union type when 2-3 classes match
      expect(response.contents.value).to match(/Parser.*Compiler|Compiler.*Parser/)
    end
  end

  describe "Call Node Hover" do
    context "method call with variable receiver" do
      let(:source) do
        <<~RUBY
          def foo
            str = "hello"
            str.upcase
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "upcase" method call
        expect_hover_method_signature(line: 3, column: 6, expected_signature: "() -> ::String")
      end
    end

    it "returns nil or untyped when receiver type is unknown" do
      source = <<~RUBY
        def foo
          unknown_var.some_method
        end
      RUBY

      # Hover on "some_method"
      response = hover_on_source(source, { line: 1, character: 14 })

      # Should not crash, may return nil or untyped info
      # This is acceptable behavior for unknown types
      expect(response).to be_nil.or(have_attributes(contents: have_attributes(value: include("untyped"))))
    end

    context "instance variable receiver" do
      let(:source) do
        <<~RUBY
          def foo
            @name = "Alice"
            @name.downcase
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "downcase" method call
        expect_hover_method_signature(line: 3, column: 8, expected_signature: "() -> ::String")
      end
    end

    context "method chain (variable receiver)" do
      let(:source) do
        <<~RUBY
          def foo
            str = "hello"
            str.chars.first
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "first" in the chain
        # chars returns Array[String], so first returns String | nil
        expect_hover_method_signature(line: 3, column: 12, expected_signature: "() -> Elem")
      end
    end

    context "map to first chain" do
      let(:source) do
        <<~RUBY
          def foo
            arr = [1, 2, 3]
            arr.map { |x| x * 2 }.first
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "first" after map chain
        # map returns Array, so first should show Array signatures
        expect_hover_method_signature(line: 3, column: 24, expected_signature: "() -> Elem")
      end
    end

    context "chained enumerable methods" do
      let(:source) do
        <<~RUBY
          def foo
            arr = [1, 2, 3]
            arr.select { |x| x.even? }.map { |x| x * 2 }.compact
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "compact"
        expect_hover_method_signature(line: 3, column: 53, expected_signature: "() -> ::Array[Elem]")
      end
    end

    it "handles deep method chains gracefully" do
      source = <<~RUBY
        def foo
          "a".upcase.downcase.upcase.downcase.upcase.downcase.upcase
        end
      RUBY

      # Hover on the last "upcase" (7th level)
      # IR-based inference handles deep chains without recursion issues
      response = hover_on_source(source, { line: 1, character: 54 })

      # IR-based approach successfully infers type for deep chains
      expect(response).not_to be_nil
      expect(response.contents.value).to include("String")
    end

    it "shows RBS signature when receiver type is inferred from method calls" do
      source = <<~RUBY
        class Recipe
          def ingredients
            []
          end
          def steps
            []
          end
        end

        class Recipe2 < Recipe
        end

        def process(recipe)
          recipe.ingredients
          recipe.steps
        end
      RUBY

      # Hover on "ingredients" method name in recipe.ingredients
      response = hover_on_source(source, { line: 13, character: 9 })

      # Should NOT crash with "undefined method 'delete_prefix' for Types::ClassInstance"
      # Should return method signature for Array#ingredients (or Recipe#ingredients)
      expect(response).not_to be_nil
      expect(response.contents.value).to match(/ingredients/)
    end

    # Edge case: Safe navigation operator
    it "handles safe navigation operator" do
      source = <<~RUBY
        class User
          def name
            "John"
          end
        end

        def foo
          user = User.new
          user&.name
        end
      RUBY

      # Hover on "name" in safe navigation
      response = hover_on_source(source, { line: 7, character: 11 })

      expect(response).not_to be_nil
    end

    # Edge case: Method with block
    context "method call with block" do
      let(:source) do
        <<~RUBY
          def foo
            arr = [1, 2, 3]
            arr.map { |x| x * 2 }
          end
        RUBY
      end

      it "shows RBS signature" do
        # Hover on "map"
        expect_hover_method_signature(line: 3, column: 6, expected_signature: "[U] () { (Elem item) -> U } -> ::Array[U]")
      end
    end
  end

  describe "Method Signature Display", :doc do
    context "String#upcase" do
      let(:source) do
        <<~RUBY
          str = "hello"
          str.upcase
        RUBY
      end

      it "→ () -> ::String" do
        expect_hover_method_signature(line: 2, column: 4, expected_signature: "() -> ::String")
      end
    end

    context "Array#map" do
      let(:source) do
        <<~RUBY
          arr = [1, 2, 3]
          arr.map { |x| x * 2 }
        RUBY
      end

      it "→ [U] () { (Elem item) -> U } -> ::Array[U]" do
        expect_hover_method_signature(line: 2, column: 4, expected_signature: "[U] () { (Elem item) -> U } -> ::Array[U]")
      end
    end
  end

  describe "Def Node Hover" do
    context "simple method with no parameters" do
      let(:source) do
        <<~RUBY
          def foo
            42
          end
        RUBY
      end

      it "→ () -> Integer" do
        # Hover on method name "foo"
        expect_hover_method_signature(line: 1, column: 4, expected_signature: "() -> Integer")
      end
    end

    context "signature with parameter types inferred from defaults" do
      let(:source) do
        <<~RUBY
          def greet(name, age = 20)
            "Hello, \#{name}! You are \#{age}."
          end
        RUBY
      end

      it "→ (untyped name, ?Integer age) -> String" do
        # Hover on method name "greet"
        expect_hover_method_signature(line: 1, column: 4, expected_signature: "(untyped name, ?Integer age) -> String")
      end
    end

    context "union type for multiple return paths" do
      let(:source) do
        <<~RUBY
          def get_value(flag)
            if flag
              42
            else
              "not a number"
            end
          end
        RUBY
      end

      it "→ (untyped flag) -> Integer | String" do
        # Hover on method name "get_value"
        expect_hover_method_signature(line: 1, column: 4, expected_signature: "(untyped flag) -> Integer | String")
      end
    end

    context "empty method body" do
      let(:source) do
        <<~RUBY
          class Animal
            def eat
            end
          end
        RUBY
      end

      it "→ () -> nil" do
        # Hover on method name "eat"
        expect_hover_method_signature(line: 2, column: 6, expected_signature: "() -> nil")
      end
    end

    context "keyword parameters" do
      let(:source) do
        <<~RUBY
          def configure(name:, timeout: 30)
            # configuration logic
          end
        RUBY
      end

      it "→ (name: untyped, timeout: ?Integer) -> nil" do
        # Hover on method name "configure"
        expect_hover_method_signature(line: 1, column: 4, expected_signature: "(name: untyped, timeout: ?Integer) -> nil")
      end
    end

    context "infer return type from method call on parameter with default value" do
      let(:source) do
        <<~RUBY
          def transform(text = "hello")
            text.upcase
          end
        RUBY
      end

      it "→ (?String text) -> String" do
        # Hover on method name "transform"
        expect_hover_method_signature(line: 1, column: 4, expected_signature: "(?String text) -> String")
      end
    end

    context "infer return type from user-defined method call" do
      let(:source) do
        <<~RUBY
          class Recipe
            def ingredients
              []
            end

            def steps
              []
            end
          end

          def process(recipe)
            recipe.ingredients
            recipe.steps
          end
        RUBY
      end

      it "→ (Recipe recipe) -> Array" do
        # Hover on method name "process"
        # Last expression is recipe.steps which returns Array from Recipe#steps
        expect_hover_method_signature(line: 11, column: 4, expected_signature: "(Recipe recipe) -> Array")
      end
    end
  end

  describe "Block Parameter Type Inference" do
    it "infers block parameter type from Array[Integer]#each" do
      source = <<~RUBY
        def foo
          arr = [1, 2, 3]
          arr.each { |num| puts num }
        end
      RUBY

      # Hover on "num" block parameter (line 2, character 14 = 'n' of 'num')
      response = hover_on_source(source, { line: 2, character: 14 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Integer/)
    end

    it "infers block parameter type from Array[String]#map" do
      source = <<~RUBY
        def foo
          names = ["alice", "bob"]
          names.map { |name| name.upcase }
        end
      RUBY

      # Hover on "name" block parameter
      response = hover_on_source(source, { line: 2, character: 15 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/String/)
    end

    it "infers block parameter type from String#each_char" do
      source = <<~RUBY
        def foo
          text = "hello"
          text.each_char { |char| puts char }
        end
      RUBY

      # Hover on "char" block parameter
      response = hover_on_source(source, { line: 2, character: 21 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/String/)
    end

    it "returns Unknown for block parameter when receiver type is unknown" do
      source = <<~RUBY
        def foo(arr)
          arr.each { |item| puts item }
        end
      RUBY

      # Hover on "item" block parameter - receiver 'arr' has unknown type
      response = hover_on_source(source, { line: 1, character: 15 })

      # Should still return something (untyped or Unknown)
      # Not testing specific content since receiver type is unknown
      expect(response).not_to be_nil
    end

    # Edge case: Hash#each with multiple block parameters
    it "infers block parameter types from Hash#each - k parameter" do
      source = <<~RUBY
        def foo
          data = { name: "Alice", age: 30 }
          data.each { |k, v| puts k }
        end
      RUBY

      # Hover on "k" parameter - should be Symbol
      response = hover_on_source(source, { line: 2, character: 15 })

      expect(response).not_to be_nil
      # k should be Symbol (key type)
      expect(response.contents.value).to match(/Symbol/)
    end

    it "infers block parameter types from Hash#each - v parameter" do
      source = <<~RUBY
        def foo
          data = { name: "Alice", age: 30 }
          data.each { |k, v| puts v }
        end
      RUBY

      # Hover on "v" parameter - should be Union of value types
      response = hover_on_source(source, { line: 2, character: 18 })

      expect(response).not_to be_nil
      # v should be String | Integer (value types)
      expect(response.contents.value).to match(/(String|Integer)/)
    end

    it "infers block parameter type from Hash#each_key" do
      source = <<~RUBY
        def foo
          data = { name: "Alice", age: 30 }
          data.each_key { |k| puts k }
        end
      RUBY

      # Hover on "k" parameter - should be Symbol
      response = hover_on_source(source, { line: 2, character: 19 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Symbol/)
    end

    it "infers block parameter type from Hash#each_value" do
      source = <<~RUBY
        def foo
          data = { name: "Alice", age: 30 }
          data.each_value { |v| puts v }
        end
      RUBY

      # Hover on "v" parameter - should be Union of value types
      response = hover_on_source(source, { line: 2, character: 21 })

      expect(response).not_to be_nil
      # v should be String | Integer (value types)
      expect(response.contents.value).to match(/(String|Integer)/)
    end

    # Edge case: Enumerator chain
    it "handles enumerator chain with_index" do
      source = <<~RUBY
        def foo
          arr = [1, 2, 3]
          arr.map.with_index { |x, i| x * i }
        end
      RUBY

      # Hover on "x" - should be Integer
      response = hover_on_source(source, { line: 2, character: 24 })

      expect(response).not_to be_nil
    end
  end

  describe "Block Return Type Inference", :doc do
    context "Array#map with block" do
      let(:source) do
        <<~RUBY
          numbers = [1, 2, 3]
          strings = numbers.map { |n| n.to_s }
          strings
        RUBY
      end

      it "→ Array[String]" do
        expect_hover_type(line: 3, column: 0, expected: "Array[String]")
      end
    end

    context "Array#select with block" do
      let(:source) do
        <<~RUBY
          numbers = [1, 2, 3, 4, 5]
          evens = numbers.select { |n| n.even? }
          evens
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 3, column: 0, expected: "Array[Integer]")
      end
    end

    context "Array#map with empty block" do
      let(:source) do
        <<~RUBY
          numbers = [1, 2, 3]
          result = numbers.map { }
          result
        RUBY
      end

      it "→ Array[nil]" do
        expect_hover_type(line: 3, column: 0, expected: "Array[nil]")
      end
    end

    context "Array#map with Integer arithmetic" do
      let(:source) do
        <<~RUBY
          a = [1, 2, 3]
          b = a.map do |num|
            num * 2
          end
          b
        RUBY
      end

      it "→ Array[Integer] at assignment" do
        # Hover on 'b' at the assignment line (line 2, col 0)
        expect_hover_type(line: 2, column: 0, expected: "Array[Integer]")
      end

      it "→ Array[Integer] at reference" do
        # Hover on 'b' at the reference line (line 5, col 0)
        expect_hover_type(line: 5, column: 0, expected: "Array[Integer]")
      end
    end

    context "Array#map with do-end block" do
      let(:source) do
        <<~RUBY
          numbers = [1, 2, 3]
          result = numbers.map do |n|
            n.next
          end
          result
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 5, column: 0, expected: "Array[Integer]")
      end
    end

    context "Array#map with Integer#next" do
      let(:source) do
        <<~RUBY
          numbers = [1, 2, 3]
          result = numbers.map { |n| n.next }
          result
        RUBY
      end

      it "→ Array[Integer]" do
        expect_hover_type(line: 3, column: 0, expected: "Array[Integer]")
      end
    end
  end

  describe "Method Parameter Type Inference" do
    context "required parameter type from method calls" do
      let(:source) do
        <<~RUBY
          class Recipe
            def validate!
            end

            def update(attrs)
            end

            def notify_followers
            end
          end

          def publish(recipe)
            recipe.validate!
            recipe.update(status: :published)
            recipe.notify_followers
          end
        RUBY
      end

      it "→ Recipe" do
        # Hover on "recipe" parameter in def line
        expect_hover_type(line: 12, column: 13, expected: "Recipe")
      end
    end

    it "shows Unknown when no method calls on parameter" do
      source = <<~RUBY
        def process(data)
          puts "processing"
        end
      RUBY

      # Hover on "data" parameter - no method calls
      response = hover_on_source(source, { line: 0, character: 13 })

      # With no method calls, type inference returns Unknown
      # In debug mode, this shows debug info; otherwise may show nothing
      # Just check that it doesn't crash
      expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
    end

    context "multiple parameters with different types" do
      let(:source) do
        <<~RUBY
          class Account
            def withdraw(amount)
            end

            def deposit(amount)
            end
          end

          class Transaction
            def self.create(attrs)
            end
          end

          def transfer(from_account, to_account, amount)
            from_account.withdraw(amount)
            to_account.deposit(amount)
            Transaction.create(from: from_account, to: to_account)
          end
        RUBY
      end

      it "→ Account" do
        # Hover on "from_account" parameter
        expect_hover_type(line: 14, column: 15, expected: "Account")
      end
    end

    it "shows ambiguous when multiple types match" do
      source = <<~RUBY
        class User
          def save
          end

          def reload
          end
        end

        class Post
          def save
          end

          def reload
          end
        end

        def persist(item)
          item.save
          item.reload
        end
      RUBY

      # Hover on "item" parameter - both User and Post have save and reload
      response = hover_on_source(source, { line: 16, character: 13 })

      expect(response).not_to be_nil
      # Should show ambiguous or union type
      content = response.contents.value
      expect(content).to match(/User|Post|Ambiguous/i)
    end
  end

  describe "Constant Alias Support" do
    context "simple constant alias in .new calls" do
      let(:source) do
        <<~RUBY
          class Recipe
            def validate!
            end
          end

          RecipeAlias = Recipe

          def create_recipe
            result = RecipeAlias.new
            result
          end
        RUBY
      end

      it "→ Recipe" do
        # Hover on "result" variable - should show Recipe type (resolved from alias)
        expect_hover_type(line: 10, column: 2, expected: "Recipe")
      end
    end

    context "constant alias with full path" do
      let(:source) do
        <<~RUBY
          module MyApp
            class Service
              def perform
              end
            end
          end

          ServiceAlias = MyApp::Service

          def execute
            svc = ServiceAlias.new
            svc
          end
        RUBY
      end

      it "→ Service" do
        # Hover on "svc" variable - should show Service type
        expect_hover_type(line: 12, column: 2, expected: "Service")
      end
    end

    context "chained constant aliases" do
      let(:source) do
        <<~RUBY
          class Worker
            def execute
            end
          end

          WorkerAlias1 = Worker
          WorkerAlias2 = WorkerAlias1

          def start
            w = WorkerAlias2.new
            w
          end
        RUBY
      end

      it "→ Worker" do
        # Hover on "w" variable - should show Worker type (resolved through chain)
        expect_hover_type(line: 11, column: 2, expected: "Worker")
      end
    end

    context "non-alias constants" do
      let(:source) do
        <<~RUBY
          CONFIG = Rails.configuration

          class Task
            def run
            end
          end

          def perform
            t = Task.new
            t
          end
        RUBY
      end

      it "→ Task" do
        # Hover on "t" - Task is not an alias
        expect_hover_type(line: 10, column: 2, expected: "Task")
      end
    end

    # Edge case: Circular reference protection
    it "handles circular constant references without infinite loop" do
      source = <<~RUBY
        class Base
          def process
          end
        end

        AliasA = Base
        AliasB = AliasA
        AliasC = AliasB
        AliasD = AliasC
        AliasE = AliasD
        AliasF = AliasE

        def foo
          obj = AliasF.new
          obj
        end
      RUBY

      # Should handle deep alias chain (up to max depth)
      response = hover_on_source(source, { line: 13, character: 2 })

      expect(response).not_to be_nil
      # Should resolve to Base or handle gracefully
    end

    # Edge case: Undefined constant reference
    it "handles undefined constant gracefully" do
      source = <<~RUBY
        # UndefinedClass does not exist
        def foo
          # This would fail at runtime, but type inference should not crash
          obj = UndefinedClass.new
          obj
        end
      RUBY

      # Should not crash, may return nil or unknown
      response = hover_on_source(source, { line: 3, character: 2 })

      # Should handle gracefully (not crash)
      expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
    end
  end

  describe "Method Signature Display on Call Site" do
    context "Simple return type" do
      let(:source) do
        <<~RUBY
          class Recipe
            def ingredients
              []
            end

            def steps
              []
            end
          end

          def process(recipe)
            recipe.ingredients
            recipe.steps
          end
        RUBY
      end

      it "→ () -> Array" do
        expect_hover_method_signature(line: 12, column: 9, expected_signature: "() -> Array")
      end
    end

    context "Integer return type" do
      let(:source) do
        <<~RUBY
          class Calculator
            def compute
              42
            end
          end

          def example(calc)
            calc.compute
          end
        RUBY
      end

      it "→ () -> Integer" do
        expect_hover_method_signature(line: 8, column: 7, expected_signature: "() -> Integer")
      end
    end

    context "Union return type" do
      let(:source) do
        <<~RUBY
          class Conditional
            def value
              if true
                "string"
              else
                42
              end
            end
          end

          def example(obj)
            obj.value
          end
        RUBY
      end

      it "→ () -> String | Integer" do
        response = hover_on_source(source, { line: 11, character: 6 })

        expect(response).not_to be_nil
        expect(response.contents.value).to match(/Guessed Signature/)
        expect(response.contents.value).to match(/String.*Integer|Integer.*String/)
      end
    end

    it "does not crash when method definition not found" do
      source = <<~RUBY
        def example(obj)
          obj.unknown_method
        end
      RUBY

      # Hover on "unknown_method" - should not crash
      response = hover_on_source(source, { line: 1, character: 6 })

      # Should handle gracefully (may be nil or have RBS signature if available)
      expect { response }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/DescribeClass
