# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Hover Integration (Smoke)" do
  include TypeGuessrTestHelper

  describe "Parameter Hover" do
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
      allow(TypeGuessr::Core::Config).to receive(:debug?).and_return(true)
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

    context "RBS method owner display" do
      let(:source) do
        <<~RUBY
          class Recipe
            def name; end
          end
          recipe = Recipe.new
          recipe.tap { |x| x }
        RUBY
      end

      it "shows method owner in debug info" do
        # Hover on "tap" method call - should show Kernel as the owner
        response = hover_on_source(source, { line: 4, character: 7 })
        expect(response.contents.value).to match(/\*\*\[TypeGuessr Debug\]/)
        expect(response.contents.value).to match(/Defined in:.*Kernel/i)
      end
    end
  end

  describe "Edge Cases" do
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

      it "does not crash on class variable hover" do
        # Class variable type inference not yet implemented
        expect_no_hover_crash(line: 3, column: 4)
      end
    end
  end

  describe "Method Call Return Type (Expression Type)" do
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
  end

  describe "Method-Call Set Heuristic" do
    context "multiple classes match method-based inference" do
      let(:source) do
        <<~RUBY
          class Parser
            def parse_source_xyz
            end
          end

          class Compiler
            def parse_source_xyz
            end
          end

          def example(obj)
            obj.parse_source_xyz
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
        # Hover on "name" in user&.name (line 9, character 11)
        response = hover_on_source(source, { line: 8, character: 11 })
        expect(response).not_to be_nil
      end
    end
  end

  describe "Block Parameter Type Inference" do
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

  describe "Method Parameter Type Inference" do
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

  describe "Method Signature Display" do
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

      it "→ () -> []" do
        expect_hover_method_signature(line: 12, column: 9, expected_signature: "() -> []")
      end
    end

    context "implicit self method call with optional parameter" do
      let(:source) do
        <<~RUBY
          def greet(name = "World")
            "Hello, \#{name}!"
          end

          greet("Alice")
        RUBY
      end

      it "shows parameter info from DefNode" do
        # Hover on "greet" in greet("Alice") call (line 5, col 0)
        expect_hover_method_signature(line: 5, column: 0, expected_signature: "(?String name) -> String")
      end
    end

    context "implicit self method call inside class" do
      let(:source) do
        <<~RUBY
          class Calculator
            def add(a, b = 10)
              a + b
            end

            def compute
              add(5, 20)
            end
          end
        RUBY
      end

      it "shows parameter info from DefNode" do
        # Hover on "add" in add(5, 20) call (line 7, col 4)
        # Return type is untyped because `a` parameter has no type info
        expect_hover_method_signature(line: 7, column: 4, expected_signature: "(untyped a, ?Integer b) -> untyped")
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

    context "method call shows same signature as method definition" do
      let(:source) do
        <<~RUBY
          class Greeter
            def greet(name = "World")
              "Hello, \#{name}!"
            end
          end

          greeter = Greeter.new
          greeter.greet("Alice")
        RUBY
      end

      it "shows parameter info from DefNode" do
        # Method definition hover should show: (?String name) -> String
        def_response = hover_on_source(source, { line: 1, character: 6 })
        # Method call hover should show the same signature
        call_response = hover_on_source(source, { line: 7, character: 10 })

        expect(def_response).not_to be_nil
        expect(call_response).not_to be_nil

        # Both should show the same parameter signature with default value type
        expect(def_response.contents.value).to include("?String name")
        expect(call_response.contents.value).to include("?String name")
      end
    end

    context "method call reuses DefNode inference for complex parameters" do
      let(:source) do
        <<~RUBY
          class Calculator
            def add(a, b = 10, *rest, key:, opt_key: "default", **kwargs, &block)
              a + b
            end
          end

          calc = Calculator.new
          calc.add(1, 2, 3, key: "x")
        RUBY
      end

      it "shows full parameter signature from DefNode" do
        # Method definition hover
        def_response = hover_on_source(source, { line: 1, character: 6 })
        # Method call hover
        call_response = hover_on_source(source, { line: 7, character: 7 })

        expect(def_response).not_to be_nil
        expect(call_response).not_to be_nil

        # DefNode should show complex parameter signature
        def_content = def_response.contents.value
        call_content = call_response.contents.value

        # Both should have "Guessed Signature"
        expect(def_content).to include("Guessed Signature")
        expect(call_content).to include("Guessed Signature")

        # Both should have the same return type (Integer from a + b)
        expect(def_content).to include("Integer")
        expect(call_content).to include("Integer")
      end
    end

    context "Union return type" do
      let(:source) do
        <<~RUBY
          class Conditional
            def conditional_value_xyz
              if true
                "string"
              else
                42
              end
            end
          end

          def example(obj)
            obj.conditional_value_xyz
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

  describe "Self-returning methods (tap, then)" do
    context "tap method signature on custom class" do
      let(:source) do
        <<~RUBY
          class Recipe
            def name; end
          end
          recipe = Recipe.new
          recipe.tap { |x| x }
        RUBY
      end

      it "shows Object#tap RBS signature" do
        # Hover on "tap" method call should show RBS Object#tap signature
        # not `(&<anonymous block>) -> Recipe`
        response = hover_on_source(source, { line: 4, character: 7 })
        expect(response).not_to be_nil
        # Should show Object#tap's RBS signature: () { (self) -> void } -> self
        expect(response.contents.value).to include("{ (self) -> void } -> self")
      end
    end
  end

  describe "initialize method" do
    context "initialize method signature" do
      let(:source) do
        <<~RUBY
          class User
            def initialize(name)
              @name = name
            end
          end
        RUBY
      end

      it "shows self as return type" do
        # Hover on `initialize` method name (line 2, column 6 is 'i' in 'initialize')
        response = hover_on_source(source, { line: 1, character: 6 })
        contents = response&.contents&.value || ""
        # The signature should include "self" as return type
        expect(contents).to include("self")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
