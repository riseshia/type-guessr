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

      expect(response.contents.value).to match(/Ambiguous type/)
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

      expect(response.contents.value).to match(/Ambiguous type/)
      expect(response.contents.value).to match(/\.\.\./)
      main_content = response.contents.value.split("**[TypeGuessr Debug]").first
      class_count = main_content.scan(/`Class[A-E]`/).size
      expect(class_count).to eq(3)
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
end
# rubocop:enable RSpec/DescribeClass
