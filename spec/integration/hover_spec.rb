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
        expect_hover_type(line: 2, column: 0, expected: "Hash[untyped, untyped]")
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
        expect_hover_type(line: 3, column: 0, expected: "Hash[String | Symbol, Integer]")
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
        expect_hover_type(line: 2, column: 0, expected: "Range[Integer]")
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

      it "→ Array[Float | Integer | String | Symbol]" do
        expect_hover_type(line: 2, column: 0, expected: "Array[Float | Integer | String | Symbol]")
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
    context "Symbol-keyed hash" do
      let(:source) do
        <<~RUBY
          user = { name: "John", age: 20 }
          user
        RUBY
      end

      it "infers HashShape with field types" do
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

      it "infers Hash type" do
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

      it "infers Hash type" do
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

      it "infers nested HashShape" do
        expect_hover_type(line: 2, column: 0, expected: "{ name: String, address: { city: String } }")
      end
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

  describe "Class Method Calls", :doc do
    context "File.read" do
      let(:source) do
        <<~RUBY
          raw = File.read("dummy.txt")
          raw
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 2, column: 0, expected: "String")
      end
    end

    context "File.exist?" do
      let(:source) do
        <<~RUBY
          exists = File.exist?("path")
          exists
        RUBY
      end

      it "→ bool" do
        expect_hover_type(line: 2, column: 0, expected: "bool")
      end
    end

    context "Dir.pwd" do
      let(:source) do
        <<~RUBY
          path = Dir.pwd
          path
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 2, column: 0, expected: "String")
      end
    end
  end

  describe "Explicit Return Handling", :doc do
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

  describe "Method-Call Based Inference" do
    context "single type when method is unique" do
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
      end

      it "infers Recipe from method calls" do
        expect_hover_type(line: 17, column: 12, expected: "Recipe")
      end
    end

    context "subclass method combined with inherited methods" do
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

          class Recipe2 < Recipe
            def notes
              "Some notes"
            end
          end

          def process(recipe)
            recipe.ingredients
            recipe.steps
            recipe.notes
            recipe
          end
        RUBY
      end

      it "infers Recipe2 from method calls with inherited methods" do
        expect_hover_type(line: 21, column: 4, expected: "Recipe2")
      end
    end

    context "parent methods only called" do
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

          class Recipe2 < Recipe
            def notes
              "Some notes"
            end
          end

          def process(recipe)
            recipe.ingredients
            recipe.steps
            recipe
          end
        RUBY
      end

      it "infers Recipe (most general type) when only parent methods are called" do
        expect_hover_type(line: 18, column: 4, expected: "Recipe")
      end
    end

    context "multiple classes match" do
      let(:source) do
        <<~RUBY
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
      end

      it "shows union of matching classes" do
        expect_hover_type(line: 16, column: 12, expected: "Cacheable | Persistable")
      end
    end

    context "too many classes match (4+)" do
      let(:source) do
        <<~RUBY
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
      end

      it "shows untyped instead of listing them" do
        expect_hover_type(line: 25, column: 12, expected: "untyped")
      end
    end
  end

  describe "Variable Scope Isolation" do
    context "same parameter name across methods" do
      let(:source) do
        <<~RUBY
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
      end

      it "isolates parameter types per method" do
        # method_a's context has no called methods - returns Unknown
        response_a = hover_on_source(source, { line: 2, character: 15 })
        expect(response_a.contents.value).to include("untyped")

        # method_b's context has called methods but cannot resolve to a class - returns Unknown
        response_b = hover_on_source(source, { line: 6, character: 4 })
        expect(response_b.contents.value).to include("untyped")
      end
    end

    context "local vs instance variable" do
      let(:source) do
        <<~RUBY
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
      end

      it "distinguishes local from instance variable" do
        expect_hover_type(line: 7, column: 4, expected: "String")
      end
    end

    context "instance variable sharing across methods" do
      let(:source) do
        <<~RUBY
          class Chef
            def prepare_recipe
              @recipe = Recipe.new
            end

            def do_something
              @recipe
            end
          end

          class Recipe
          end
        RUBY
      end

      it "shares instance variable type across methods within same class" do
        expect_hover_type(line: 7, column: 6, expected: "Recipe")
      end
    end

    context "instance variable usage before assignment" do
      let(:source) do
        <<~RUBY
          class Chef
            def do_something
              @recipe
            end

            def prepare_recipe
              @recipe = Recipe.new
            end
          end

          class Recipe
          end
        RUBY
      end

      it "can see instance variable assigned in later method via deferred lookup" do
        # Deferred lookup at inference time resolves forward references
        # Even when usage comes before assignment in method order,
        # the instance variable can be resolved through the registry
        response = hover_on_source(source, { line: 2, character: 6 })
        expect(response.contents.value).to include("Recipe")
      end
    end

    context "block-local variable shadowing" do
      let(:source) do
        <<~RUBY
          def foo
            x = 1
            [1, 2].each do |x|
              x
            end
          end
        RUBY
      end

      it "handles block parameter correctly" do
        response = hover_on_source(source, { line: 3, character: 4 })
        expect(response).not_to be_nil
      end
    end

    context "top-level variable" do
      let(:source) do
        <<~RUBY
          x = 42
          x
        RUBY
      end

      it "infers type at top level" do
        expect_hover_type(line: 2, column: 0, expected: "Integer")
      end
    end

    context "singleton class scope" do
      let(:source) do
        <<~RUBY
          class Foo
            class << self
              def bar
                x = "singleton"
                x
              end
            end
          end
        RUBY
      end

      it "infers type in singleton class" do
        expect_hover_type(line: 5, column: 6, expected: "String")
      end
    end
  end

  describe "Parameter Hover" do
    context "optional parameter with default" do
      let(:source) do
        <<~RUBY
          def greet(name = "World")
            name.upcase
          end
        RUBY
      end

      it "infers type from default value" do
        expect_hover_type(line: 2, column: 4, expected: "String")
      end
    end

    context "rest parameter" do
      let(:source) do
        <<~RUBY
          def greet(*names)
            names.join
          end
        RUBY
      end

      it "infers Array type" do
        expect_hover_type(line: 2, column: 4, expected: "Array[untyped]")
      end
    end

    context "block parameter" do
      let(:source) do
        <<~RUBY
          def execute(&block)
            block.call
          end
        RUBY
      end

      it "infers Proc type" do
        expect_hover_type(line: 2, column: 4, expected: "Proc")
      end
    end

    context "forwarding parameter" do
      let(:source) do
        <<~RUBY
          def forward(...)
            other_method(...)
          end
        RUBY
      end

      it "shows forwarding type" do
        expect_hover_response(line: 1, column: 12)
      end
    end

    context "keyword rest parameter" do
      let(:source) do
        <<~RUBY
          def process(**kwargs)
            kwargs.keys
          end
        RUBY
      end

      it "infers Hash type" do
        expect_hover_type(line: 2, column: 2, expected: "Hash")
      end
    end

    context "optional parameter with .new default" do
      let(:source) do
        <<~RUBY
          class User
          end

          def foo(x = User.new)
            x
          end
        RUBY
      end

      it "infers type from default" do
        expect_hover_type(line: 5, column: 2, expected: "User")
      end
    end

    context "optional parameter with integer default" do
      let(:source) do
        <<~RUBY
          def foo(x = 42)
            x
          end
        RUBY
      end

      it "infers Integer type" do
        expect_hover_type(line: 2, column: 2, expected: "Integer")
      end
    end
  end

  describe "Type Definition Links" do
    context "link to class definition" do
      let(:source) do
        <<~RUBY
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
      end

      it "includes link in hover" do
        response = hover_on_source(source, { line: 11, character: 4 })
        expect(response.contents.value).to match(/Guessed Type:/)
        expect(response.contents.value).to match(/\[`Recipe`\]\(file:/)
      end
    end
  end

  describe "Debug Mode" do
    before do
      allow(RubyLsp::TypeGuessr::Config).to receive(:debug?).and_return(true)
    end

    context "debug info display" do
      let(:source) do
        <<~RUBY
          def process(item)
            item.save
            item
          end
        RUBY
      end

      it "shows debug info when enabled" do
        response = hover_on_source(source, { line: 0, character: 12 })
        expect(response.contents.value).to match(/\*\*\[TypeGuessr Debug\]/)
        expect(response.contents.value).to match(/Reason:/)
        expect(response.contents.value).to match(/Method calls:/)
      end
    end
  end

  describe "Edge Cases" do
    context "self keyword" do
      let(:source) do
        <<~RUBY
          class Foo
            def bar
              self
            end
          end
        RUBY
      end

      it "infers class type" do
        expect_hover_type(line: 3, column: 4, expected: "Foo")
      end
    end

    context "global variable" do
      let(:source) do
        <<~RUBY
          $global = "test"
          $global.upcase
        RUBY
      end

      it "shows hover response" do
        # Global variable type inference not yet implemented
        expect_hover_response(line: 2, column: 0)
      end
    end

    context "class variable" do
      let(:source) do
        <<~RUBY
          class Counter
            @@count = 0
            @@count.succ
          end
        RUBY
      end

      it "shows hover response" do
        # Class variable type inference not yet implemented
        expect_hover_response(line: 3, column: 4)
      end
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

      it "→ String (not Integer)" do
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

      it "tracks type changes to String" do
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

      it "tracks type changes to Hash" do
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

      it "tracks type changes to Hash" do
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

      it "tracks type changes to Hash" do
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

      it "falls back to VariableTypeResolver" do
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

      it "infers union type" do
        expect_hover_type(line: 8, column: 2, expected: "Integer | String | Symbol")
      end
    end

    context "ternary operator" do
      let(:source) do
        <<~RUBY
          def foo(flag)
            x = flag ? 1 : "str"
            x
          end
        RUBY
      end

      it "infers union type" do
        expect_hover_type(line: 3, column: 2, expected: "Integer | String")
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

      it "handles unless" do
        expect_hover_response(line: 6, column: 2)
      end
    end

    context "||= compound assignment" do
      let(:source) do
        <<~RUBY
          def foo
            x = nil
            x ||= 1
            x
          end
        RUBY
      end

      it "infers optional type" do
        expect_hover_type(line: 4, column: 2, expected: "?Integer")
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

      it "infers union type" do
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

      it "infers String type from String#+" do
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

      it "handles guard clause" do
        expect_hover_type(line: 4, column: 2, expected: "Integer")
      end
    end
  end

  describe "Method Call Return Type (Expression Type)" do
    context "method call assignment" do
      let(:source) do
        <<~RUBY
          def example
            hoge = 1
            hoge2 = hoge.to_s
            hoge2
          end
        RUBY
      end

      it "infers variable type" do
        expect_hover_type(line: 4, column: 2, expected: "String")
      end
    end

    context "chained method call assignment" do
      let(:source) do
        <<~RUBY
          def example
            name = "hello"
            result = name.upcase.length
            result
          end
        RUBY
      end

      it "infers variable type" do
        expect_hover_type(line: 4, column: 2, expected: "Integer")
      end
    end

    context "user-defined class method assignment" do
      let(:source) do
        <<~RUBY
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
      end

      it "does not crash" do
        response = hover_on_source(source, { line: 9, character: 2 })
        expect(response).not_to be_nil
      end
    end
  end

  describe "User-Defined Method Return Type" do
    # NOTE: These tests use spec_helper's with_server_and_addon which indexes test sources
    # in both TypeGuessr's VariableIndex and ruby-lsp's RubyIndexer.

    context "literal return" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers return type" do
        expect_hover_type(line: 9, column: 2, expected: "String")
      end
    end

    context "empty method body" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers nil" do
        expect_hover_type(line: 8, column: 2, expected: "nil")
      end
    end

    context "explicit return statement" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers return type" do
        expect_hover_type(line: 9, column: 2, expected: "Integer")
      end
    end

    context "multiple return paths" do
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

          def example
            obj = Conditional.new
            result = obj.value
            result
          end
        RUBY
      end

      it "infers union type" do
        response = hover_on_source(source, { line: 12, character: 2 })
        expect(response.contents.value).to match(/String.*Integer|Integer.*String/)
      end
    end

    context "nested method calls" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers Integer" do
        expect_hover_type(line: 9, column: 2, expected: "Integer")
      end
    end

    context "RBS fallback" do
      let(:source) do
        <<~RUBY
          def example
            arr = [1, 2, 3]
            result = arr.map { |x| x * 2 }
            result
          end
        RUBY
      end

      it "uses RBS when available" do
        expect_hover_type(line: 4, column: 2, expected: "Array[Integer]")
      end
    end

    context "implicit self method call" do
      let(:source) do
        <<~RUBY
          class Config
            def default_config
              { "enabled" => true }
            end

            def load_config
              default_config
            end
          end
        RUBY
      end

      it "infers return type from same-class method" do
        expect_hover_type(line: 7, column: 6, expected: "Hash[String, true]")
      end
    end
  end

  describe "Method-Call Set Heuristic" do
    context "unique method pattern" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers type from method pattern" do
        expect_hover_type(line: 9, column: 2, expected: "Document")
      end
    end

    context "multiple method patterns" do
      let(:source) do
        <<~RUBY
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
      end

      it "infers receiver type" do
        expect_hover_type(line: 12, column: 2, expected: "Widget")
      end
    end

    context "multiple classes match method-based inference" do
      let(:source) do
        <<~RUBY
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
      end

      it "shows union type" do
        response = hover_on_source(source, { line: 14, character: 2 })
        expect(response.contents.value).to match(/Parser.*Compiler|Compiler.*Parser/)
      end
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

    context "unknown receiver type" do
      let(:source) do
        <<~RUBY
          def foo
            unknown_var.some_method
          end
        RUBY
      end

      it "returns nil or untyped" do
        response = hover_on_source(source, { line: 1, character: 14 })
        expect(response).to be_nil.or(have_attributes(contents: have_attributes(value: include("untyped"))))
      end
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

    context "deep method chains" do
      let(:source) do
        <<~RUBY
          def foo
            "a".upcase.downcase.upcase.downcase.upcase.downcase.upcase
          end
        RUBY
      end

      it "handles gracefully" do
        response = hover_on_source(source, { line: 1, character: 54 })
        expect(response).not_to be_nil
        expect(response.contents.value).to include("String")
      end
    end

    context "receiver type inferred from method calls" do
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

          class Recipe2 < Recipe
          end

          def process(recipe)
            recipe.ingredients
            recipe.steps
          end
        RUBY
      end

      it "shows RBS signature" do
        response = hover_on_source(source, { line: 13, character: 9 })
        expect(response).not_to be_nil
        expect(response.contents.value).to match(/ingredients/)
      end
    end

    context "safe navigation operator" do
      let(:source) do
        <<~RUBY
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
      end

      it "handles safe navigation" do
        response = hover_on_source(source, { line: 7, character: 11 })
        expect(response).not_to be_nil
      end
    end

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
    context "Array[Integer]#each" do
      let(:source) do
        <<~RUBY
          def foo
            arr = [1, 2, 3]
            arr.each { |num| puts num }
          end
        RUBY
      end

      it "infers block parameter type" do
        expect_hover_type(line: 3, column: 14, expected: "Integer")
      end
    end

    context "Array[String]#map" do
      let(:source) do
        <<~RUBY
          def foo
            names = ["alice", "bob"]
            names.map { |name| name.upcase }
          end
        RUBY
      end

      it "infers block parameter type" do
        expect_hover_type(line: 3, column: 15, expected: "String")
      end
    end

    context "String#each_char" do
      let(:source) do
        <<~RUBY
          def foo
            text = "hello"
            text.each_char { |char| puts char }
          end
        RUBY
      end

      it "infers block parameter type" do
        expect_hover_type(line: 3, column: 21, expected: "String")
      end
    end

    context "unknown receiver type" do
      let(:source) do
        <<~RUBY
          def foo(arr)
            arr.each { |item| puts item }
          end
        RUBY
      end

      it "returns something" do
        response = hover_on_source(source, { line: 1, character: 15 })
        expect(response).not_to be_nil
      end
    end

    context "Hash#each - k parameter" do
      let(:source) do
        <<~RUBY
          def foo
            data = { name: "Alice", age: 30 }
            data.each { |k, v| puts k }
          end
        RUBY
      end

      it "infers Symbol" do
        expect_hover_type(line: 3, column: 15, expected: "Symbol")
      end
    end

    context "Hash#each - v parameter" do
      let(:source) do
        <<~RUBY
          def foo
            data = { name: "Alice", age: 30 }
            data.each { |k, v| puts v }
          end
        RUBY
      end

      it "infers union type" do
        response = hover_on_source(source, { line: 2, character: 18 })
        expect(response).not_to be_nil
        expect(response.contents.value).to match(/(String|Integer)/)
      end
    end

    context "Hash#each_key" do
      let(:source) do
        <<~RUBY
          def foo
            data = { name: "Alice", age: 30 }
            data.each_key { |k| puts k }
          end
        RUBY
      end

      it "infers Symbol" do
        expect_hover_type(line: 3, column: 19, expected: "Symbol")
      end
    end

    context "Hash#each_value" do
      let(:source) do
        <<~RUBY
          def foo
            data = { name: "Alice", age: 30 }
            data.each_value { |v| puts v }
          end
        RUBY
      end

      it "infers union type" do
        response = hover_on_source(source, { line: 2, character: 21 })
        expect(response).not_to be_nil
        expect(response.contents.value).to match(/(String|Integer)/)
      end
    end

    context "enumerator chain with_index" do
      let(:source) do
        <<~RUBY
          def foo
            arr = [1, 2, 3]
            arr.map.with_index { |x, i| x * i }
          end
        RUBY
      end

      it "handles enumerator chain" do
        response = hover_on_source(source, { line: 2, character: 24 })
        expect(response).not_to be_nil
      end
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

    context "no method calls on parameter" do
      let(:source) do
        <<~RUBY
          def process(data)
            puts "processing"
          end
        RUBY
      end

      it "shows Unknown" do
        response = hover_on_source(source, { line: 0, character: 13 })
        expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
      end
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

    context "multiple types match" do
      let(:source) do
        <<~RUBY
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
      end

      it "shows ambiguous or union type" do
        response = hover_on_source(source, { line: 16, character: 13 })
        expect(response).not_to be_nil
        content = response.contents.value
        expect(content).to match(/User|Post|Ambiguous/i)
      end
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

      it "→ MyApp::Service" do
        # Hover on "svc" variable - should show full path Service type
        expect_hover_type(line: 12, column: 2, expected: "MyApp::Service")
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

    context "deep alias chain (circular reference protection)" do
      let(:source) do
        <<~RUBY
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
      end

      it "handles without infinite loop" do
        response = hover_on_source(source, { line: 13, character: 2 })
        expect(response).not_to be_nil
      end
    end

    context "undefined constant reference" do
      let(:source) do
        <<~RUBY
          # UndefinedClass does not exist
          def foo
            # This would fail at runtime, but type inference should not crash
            obj = UndefinedClass.new
            obj
          end
        RUBY
      end

      it "handles gracefully" do
        response = hover_on_source(source, { line: 3, character: 2 })
        expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
      end
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

    context "method definition not found" do
      let(:source) do
        <<~RUBY
          def example(obj)
            obj.unknown_method
          end
        RUBY
      end

      it "does not crash" do
        response = hover_on_source(source, { line: 1, character: 6 })
        expect { response }.not_to raise_error
      end
    end
  end

  describe "Container Mutating Methods - Current Line Hover", :doc do
    context "Hash indexed assignment with string key" do
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

    context "Hash indexed assignment with symbol key" do
      let(:source) do
        <<~RUBY
          a = { a: 1 }
          a[:b] = "x"
        RUBY
      end

      it "shows both fields on assignment line" do
        response = hover_on_source(source, { line: 1, character: 0 })
        expect(response).not_to be_nil
        expect(response.contents.value).to include("a: Integer")
        expect(response.contents.value).to include("b: String")
      end
    end

    context "Array indexed assignment" do
      let(:source) do
        <<~RUBY
          a = [1]
          a[0] = "x"
        RUBY
      end

      it "→ Array with union type on assignment line" do
        response = hover_on_source(source, { line: 1, character: 0 })
        expect(response).not_to be_nil
        expect(response.contents.value).to match(/Array/)
        expect(response.contents.value).to match(/(Integer|String)/)
      end
    end

    context "Array << operator" do
      let(:source) do
        <<~RUBY
          a = [1]
          a << "x"
        RUBY
      end

      it "→ Array with union type on assignment line" do
        response = hover_on_source(source, { line: 1, character: 0 })
        expect(response).not_to be_nil
        expect(response.contents.value).to match(/Array/)
        expect(response.contents.value).to match(/(Integer|String)/)
      end
    end
  end

  describe "Parameter Inference via Instance Variable" do
    context "parameter assigned to instance variable with method calls" do
      let(:source) do
        <<~RUBY
          class RuntimeAdapter
            def find_node_by_key(key)
            end
          end

          class GraphBuilder
            def initialize(adapter)
              @adapter = adapter
            end

            def build
              @adapter.find_node_by_key("key")
            end
          end
        RUBY
      end

      it "infers parameter type from methods called on instance variable" do
        # Hover on "adapter" parameter in initialize - should infer RuntimeAdapter
        expect_hover_type(line: 7, column: 20, expected: "RuntimeAdapter")
      end

      it "infers instance variable type from method calls" do
        # Hover on "@adapter" in build method - should infer RuntimeAdapter
        expect_hover_type(line: 12, column: 6, expected: "RuntimeAdapter")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
