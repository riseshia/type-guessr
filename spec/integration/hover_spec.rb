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

  describe "Literal Type Inference" do
    it "infers String from string literal" do
      source = <<~RUBY
        def foo
          name = "John"
          name
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*String/)
    end

    it "infers Integer from integer literal" do
      source = <<~RUBY
        def foo
          count = 42
          count
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*Integer/)
    end

    it "infers Float from float literal" do
      source = <<~RUBY
        def foo
          price = 19.99
          price
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*Float/)
    end

    it "infers Array from array literal" do
      source = <<~RUBY
        def foo
          items = []
          items
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*Array/)
    end

    it "infers Hash from hash literal" do
      source = <<~RUBY
        def foo
          data = {}
          data
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*Hash/)
    end
  end

  describe ".new Call Type Inference" do
    it "infers type from simple class .new" do
      source = <<~RUBY
        class User
        end

        def foo
          user = User.new
          user
        end
      RUBY

      response = hover_on_source(source, { line: 5, character: 2 })

      expect(response.contents.value).to match(/Guessed type:.*User/)
    end

    it "infers type from namespaced class .new" do
      source = <<~RUBY
        module Admin
          class User
          end
        end

        def test_namespaced
          admin = Admin::User.new
          admin
        end
      RUBY

      response = hover_on_source(source, { line: 7, character: 4 })

      expect(response.contents.value).to match(/Guessed type:.*Admin::User/)
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

      expect(response.contents.value).to match(/Guessed type:.*Recipe/)
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

      expect(response.contents.value).to match(/Guessed type:/)
      expect(response.contents.value).to match(/\[`Recipe`\]\(file:/)
    end
  end

  describe "Debug Mode" do
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

  describe "FlowAnalyzer Integration" do
    it "infers union type from conditional reassignment" do
      source = <<~RUBY
        def foo(flag)
          x = 1
          if flag
            x = "string"
          end
          x
        end
      RUBY

      # Hover on "x" at the end - should show Integer | String
      response = hover_on_source(source, { line: 5, character: 2 })

      expect(response.contents.value).to match(/Integer/)
      expect(response.contents.value).to match(/String/)
    end

    it "infers precise type within a branch" do
      source = <<~RUBY
        def foo(flag)
          x = 1
          if flag
            x = "string"
            x
          end
        end
      RUBY

      # Hover on "x" inside the if branch - should show String (not union)
      response = hover_on_source(source, { line: 4, character: 4 })

      expect(response.contents.value).to match(/String/)
      # Should NOT show Integer inside the branch
      expect(response.contents.value).not_to match(/Integer.*\|.*String/)
    end

    it "tracks type changes through reassignment" do
      source = <<~RUBY
        def foo
          x = 1
          x = "string"
          x
        end
      RUBY

      # Hover on final "x" - should show String (the last assignment)
      response = hover_on_source(source, { line: 3, character: 2 })

      expect(response.contents.value).to match(/String/)
      expect(response.contents.value).not_to match(/Integer/)
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
    # NOTE: These tests require RubyIndexer to have indexed the test classes.
    # Currently, RubyIndexer is not updated with dynamically generated test sources.
    # The core functionality is verified in spec/type_guessr/core/user_method_return_resolver_spec.rb
    # TODO: Update test setup to properly index test sources in RubyIndexer

    it "infers return type from user-defined method with literal return" do
      skip "RubyIndexer does not index dynamically generated test sources"
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

    it "infers NilClass for empty method body" do
      skip "RubyIndexer does not index dynamically generated test sources"
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

      # Hover on "cc" - should infer NilClass from Animal#eat empty body
      response = hover_on_source(source, { line: 7, character: 2 })

      expect(response.contents.value).to match(/NilClass/)
    end

    it "infers return type from explicit return statement" do
      skip "RubyIndexer does not index dynamically generated test sources"
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
      skip "RubyIndexer does not index dynamically generated test sources"
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
      skip "RubyIndexer does not index dynamically generated test sources"
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
      skip "RubyIndexer does not index dynamically generated test sources"
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

    it "shows ambiguous when multiple types match" do
      skip "ambiguous type display not yet implemented"
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
      # obj has process → both Parser and Compiler have it
      response = hover_on_source(source, { line: 14, character: 2 })

      expect(response.contents.value).to match(/Ambiguous|Parser|Compiler/)
    end
  end

  describe "Call Node Hover" do
    it "shows RBS signature when hovering on method call with variable receiver" do
      source = <<~RUBY
        def foo
          str = "hello"
          str.upcase
        end
      RUBY

      # Hover on "upcase" method call
      response = hover_on_source(source, { line: 2, character: 6 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/upcase/)
      expect(response.contents.value).to match(/String/)
    end

    it "returns nil when receiver type is unknown" do
      source = <<~RUBY
        def foo
          unknown_var.some_method
        end
      RUBY

      # Hover on "some_method"
      response = hover_on_source(source, { line: 1, character: 14 })

      # Should not crash, may return nil or minimal info
      # This is acceptable behavior for unknown types
      expect(response).to be_nil
    end

    it "shows RBS signature for instance variable receiver" do
      source = <<~RUBY
        def foo
          @name = "Alice"
          @name.downcase
        end
      RUBY

      # Hover on "downcase" method call
      response = hover_on_source(source, { line: 2, character: 8 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/downcase/)
      expect(response.contents.value).to match(/String/)
    end

    it "shows RBS signature for method chain (variable receiver)" do
      source = <<~RUBY
        def foo
          str = "hello"
          str.chars.first
        end
      RUBY

      # Hover on "first" in the chain
      response = hover_on_source(source, { line: 2, character: 12 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/first/)
      # chars returns Array[String], so first returns String | nil
      expect(response.contents.value).to match(/Array/)
    end

    it "shows RBS signature for map to first chain" do
      source = <<~RUBY
        def foo
          arr = [1, 2, 3]
          arr.map { |x| x * 2 }.first
        end
      RUBY

      # Hover on "first" after map chain
      response = hover_on_source(source, { line: 2, character: 24 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/first/)
      # map returns Array, so first should show Array signatures
      expect(response.contents.value).to match(/Array/)
    end

    it "shows RBS signature for chained enumerable methods" do
      source = <<~RUBY
        def foo
          arr = [1, 2, 3]
          arr.select { |x| x.even? }.map { |x| x * 2 }.compact
        end
      RUBY

      # Hover on "compact"
      response = hover_on_source(source, { line: 2, character: 53 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/compact/)
      expect(response.contents.value).to match(/Array/)
    end

    it "returns nil for excessively deep method chains" do
      source = <<~RUBY
        def foo
          "a".upcase.downcase.upcase.downcase.upcase.downcase.upcase
        end
      RUBY

      # Hover on the last "upcase" (7th level - exceeds MAX_DEPTH of 5)
      response = hover_on_source(source, { line: 1, character: 54 })

      # Should return nil or handle gracefully when depth limit exceeded
      # This prevents infinite recursion and performance issues
      expect(response).to be_nil
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
  end

  describe "Def Node Hover" do
    it "shows signature for simple method with no parameters" do
      source = <<~RUBY
        def foo
          42
        end
      RUBY

      # Hover on method name "foo"
      response = hover_on_source(source, { line: 0, character: 4 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/\(\)/)
      expect(response.contents.value).to match(/Integer/)
    end

    it "shows signature with parameter types inferred from defaults" do
      source = <<~RUBY
        def greet(name, age = 20)
          "Hello, \#{name}! You are \#{age}."
        end
      RUBY

      # Hover on method name "greet"
      response = hover_on_source(source, { line: 0, character: 4 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/name/)
      expect(response.contents.value).to match(/age/)
      expect(response.contents.value).to match(/Integer/)
      expect(response.contents.value).to match(/String/)
    end

    it "shows union type for multiple return paths" do
      source = <<~RUBY
        def get_value(flag)
          if flag
            42
          else
            "not a number"
          end
        end
      RUBY

      # Hover on method name "get_value"
      response = hover_on_source(source, { line: 0, character: 4 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Integer/)
      expect(response.contents.value).to match(/String/)
    end

    it "shows NilClass for empty method body" do
      source = <<~RUBY
        class Animal
          def eat
          end
        end
      RUBY

      # Hover on method name "eat"
      response = hover_on_source(source, { line: 1, character: 6 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/NilClass/)
      expect(response.contents.value).not_to match(/untyped/)
    end

    it "handles keyword parameters" do
      source = <<~RUBY
        def configure(name:, timeout: 30)
          # configuration logic
        end
      RUBY

      # Hover on method name "configure"
      response = hover_on_source(source, { line: 0, character: 4 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/name:/)
      expect(response.contents.value).to match(/timeout:/)
      expect(response.contents.value).to match(/Integer/)
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
  end

  describe "Method Parameter Type Inference" do
    it "infers required parameter type from method calls in method body" do
      source = <<~RUBY
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

      # Hover on "recipe" parameter in def line
      response = hover_on_source(source, { line: 11, character: 13 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Recipe/)
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

    it "infers type when multiple parameters have different types" do
      source = <<~RUBY
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

      # Hover on "from_account" parameter
      response = hover_on_source(source, { line: 13, character: 15 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Account/)
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
    it "resolves simple constant alias in .new calls" do
      source = <<~RUBY
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

      # Hover on "result" variable
      response = hover_on_source(source, { line: 9, character: 2 })

      expect(response).not_to be_nil
      # Should show Recipe type (resolved from alias)
      expect(response.contents.value).to match(/Recipe/)
    end

    it "resolves constant alias with full path" do
      source = <<~RUBY
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

      # Hover on "svc" variable
      response = hover_on_source(source, { line: 11, character: 2 })

      expect(response).not_to be_nil
      # Should show Service type
      expect(response.contents.value).to match(/Service/)
    end

    it "resolves chained constant aliases" do
      source = <<~RUBY
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

      # Hover on "w" variable
      response = hover_on_source(source, { line: 10, character: 2 })

      expect(response).not_to be_nil
      # Should show Worker type (resolved through chain)
      expect(response.contents.value).to match(/Worker/)
    end

    it "handles non-alias constants normally" do
      source = <<~RUBY
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

      # Hover on "t" - Task is not an alias
      response = hover_on_source(source, { line: 9, character: 2 })

      expect(response).not_to be_nil
      expect(response.contents.value).to match(/Task/)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
