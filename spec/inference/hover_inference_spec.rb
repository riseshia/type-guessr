# frozen_string_literal: true

require "spec_helper"
require "prism"
require "ruby_indexer/ruby_indexer"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Hover Inference" do
  describe "Class Method Calls", :doc do
    context "File.read" do
      let(:source) do
        <<~RUBY
          raw = File.read("dummy.txt")
          raw
        RUBY
      end

      it "→ String" do
        expect_inferred_type(line: 2, column: 0, expected: "String")
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
        expect_inferred_type(line: 2, column: 0, expected: "bool")
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
        expect_inferred_type(line: 2, column: 0, expected: "String")
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
        expect_inferred_type(line: 17, column: 12, expected: "Recipe")
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
        expect_inferred_type(line: 21, column: 4, expected: "Recipe2")
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
        expect_inferred_type(line: 18, column: 4, expected: "Recipe")
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
        expect_inferred_type(line: 16, column: 12, expected: "Cacheable | Persistable")
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
        expect_inferred_type(line: 25, column: 12, expected: "untyped")
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
        expect_inferred_type(line: 2, column: 4, expected: "String")
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
        expect_inferred_type(line: 2, column: 4, expected: "Array[untyped]")
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
        expect_inferred_type(line: 2, column: 4, expected: "Proc")
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

      it "infers Hash[Symbol, untyped] type" do
        expect_inferred_type(line: 2, column: 2, expected: "Hash[Symbol, untyped]")
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
        expect_inferred_type(line: 5, column: 2, expected: "User")
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
        expect_inferred_type(line: 2, column: 2, expected: "Integer")
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
        expect_inferred_type(line: 3, column: 4, expected: "Foo")
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
        expect_inferred_type(line: 4, column: 2, expected: "String")
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
        expect_inferred_type(line: 4, column: 2, expected: "Integer")
      end
    end
  end

  describe "User-Defined Method Return Type" do
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
        expect_inferred_type(line: 9, column: 2, expected: "String")
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
        expect_inferred_type(line: 8, column: 2, expected: "nil")
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
        expect_inferred_type(line: 9, column: 2, expected: "Integer")
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
        expect_inferred_type(line: 9, column: 2, expected: "Integer")
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
        expect_inferred_type(line: 4, column: 2, expected: "Array[Integer]")
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
        expect_inferred_type(line: 7, column: 6, expected: "Hash[String, true]")
      end
    end
  end

  describe "Method-Call Set Heuristic" do
    context "unique method pattern" do
      let(:source) do
        <<~RUBY
          class Document
            def document_content_xyz
              "doc"
            end
          end

          def example(obj)
            obj.document_content_xyz
            obj
          end
        RUBY
      end

      it "infers type from method pattern" do
        expect_inferred_type(line: 9, column: 2, expected: "Document")
      end
    end

    context "multiple method patterns" do
      let(:source) do
        <<~RUBY
          class Widget
            def render_widget
            end

            def update_widget
            end
          end

          def example(obj)
            obj.render_widget
            obj.update_widget
            obj
          end
        RUBY
      end

      it "infers receiver type" do
        expect_inferred_type(line: 12, column: 2, expected: "Widget")
      end
    end

    context "infer return type from Unknown receiver with unique method" do
      let(:source) do
        <<~RUBY
          class Store
            def depot
              42
            end
          end

          def example(store)
            result = store.depot
            result
          end
        RUBY
      end

      it "infers return type from inferred receiver" do
        # store parameter is Unknown (no called_methods)
        # but depot is unique to Store, so we infer Store#depot return type
        expect_inferred_type(line: 8, column: 2, expected: "Integer")
      end
    end

    context "infer return type when receiver is from complex method" do
      let(:source) do
        <<~RUBY
          class Store
            def depot
              42
            end
          end

          def get_store(param)
            param.unknown_method # returns Unknown
          end

          def example
            store = get_store(nil)
            result = store.depot
            result
          end
        RUBY
      end

      it "infers return type from inferred receiver" do
        # store has Unknown type (from get_store which returns Unknown)
        # depot is unique to Store, so we infer Store#depot return type
        expect_inferred_type(line: 14, column: 2, expected: "Integer")
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
        expect_inferred_signature(line: 1, column: 4, expected_signature: "() -> Integer")
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
        expect_inferred_signature(line: 1, column: 4, expected_signature: "(untyped name, ?Integer age) -> String")
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
        expect_inferred_signature(line: 1, column: 4, expected_signature: "(untyped flag) -> Integer | String")
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
        expect_inferred_signature(line: 2, column: 6, expected_signature: "() -> nil")
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
        expect_inferred_signature(line: 1, column: 4, expected_signature: "(name: untyped, timeout: ?Integer) -> nil")
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
        expect_inferred_signature(line: 1, column: 4, expected_signature: "(?String text) -> String")
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

      it "→ (Recipe recipe) -> []" do
        # Hover on method name "process"
        # Last expression is recipe.steps which returns [] (empty TupleType) from Recipe#steps
        expect_inferred_signature(line: 11, column: 4, expected_signature: "(Recipe recipe) -> []")
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
        expect_inferred_type(line: 3, column: 14, expected: "Integer")
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
        expect_inferred_type(line: 3, column: 15, expected: "String")
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
        expect_inferred_type(line: 3, column: 21, expected: "String")
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
        expect_inferred_type(line: 3, column: 15, expected: "Symbol")
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
        expect_inferred_type(line: 3, column: 19, expected: "Symbol")
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
        expect_inferred_type(line: 3, column: 0, expected: "Array[String]")
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
        expect_inferred_type(line: 3, column: 0, expected: "Array[Integer]")
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
        expect_inferred_type(line: 3, column: 0, expected: "Array[nil]")
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
        expect_inferred_type(line: 2, column: 0, expected: "Array[Integer]")
      end

      it "→ Array[Integer] at reference" do
        # Hover on 'b' at the reference line (line 5, col 0)
        expect_inferred_type(line: 5, column: 0, expected: "Array[Integer]")
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
        expect_inferred_type(line: 5, column: 0, expected: "Array[Integer]")
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
        expect_inferred_type(line: 3, column: 0, expected: "Array[Integer]")
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
        expect_inferred_type(line: 12, column: 13, expected: "Recipe")
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
        expect_inferred_type(line: 14, column: 15, expected: "Account")
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
        expect_inferred_type(line: 10, column: 2, expected: "Recipe")
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
        expect_inferred_type(line: 12, column: 2, expected: "MyApp::Service")
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
        expect_inferred_type(line: 11, column: 2, expected: "Worker")
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
        expect_inferred_type(line: 10, column: 2, expected: "Task")
      end
    end
  end

  describe "Parameter Inference via Instance Variable" do
    context "parameter assigned to instance variable with method calls" do
      let(:source) do
        <<~RUBY
          class TestRuntimeAdapter
            def find_test_node_by_key(key)
            end
          end

          class TestGraphBuilder
            def initialize(adapter)
              @adapter = adapter
            end

            def build
              @adapter.find_test_node_by_key("key")
            end
          end
        RUBY
      end

      it "infers parameter type from methods called on instance variable" do
        # Hover on "adapter" parameter in initialize - should infer TestRuntimeAdapter
        expect_inferred_type(line: 7, column: 20, expected: "TestRuntimeAdapter")
      end

      it "infers instance variable type from method calls" do
        # Hover on "@adapter" in build method - should infer TestRuntimeAdapter
        expect_inferred_type(line: 12, column: 6, expected: "TestRuntimeAdapter")
      end
    end
  end

  describe "Self-returning methods (tap, then)" do
    context "tap block parameter" do
      let(:source) do
        <<~RUBY
          class Recipe
            def name; end
          end
          recipe = Recipe.new
          recipe.tap { |x| x }
        RUBY
      end

      it "infers block parameter as receiver type" do
        # Hover on "x" in the block - should be Recipe
        expect_inferred_type(line: 5, column: 17, expected: "Recipe")
      end
    end

    context "tap return type" do
      let(:source) do
        <<~RUBY
          class Recipe
            def name; end
          end
          y = Recipe.new.tap { |x| nil }
          y
        RUBY
      end

      it "infers return type as receiver type" do
        # Hover on "y" on last line - should be Recipe
        expect_inferred_type(line: 5, column: 0, expected: "Recipe")
      end
    end

    context "tap chained" do
      let(:source) do
        <<~RUBY
          class Recipe
            def name; end
          end
          z = Recipe.new.tap { }.tap { |r| r }
          z
        RUBY
      end

      it "preserves receiver type through chain" do
        # Hover on "z" - should still be Recipe
        expect_inferred_type(line: 5, column: 0, expected: "Recipe")
      end
    end

    context "Array tap" do
      let(:source) do
        <<~RUBY
          arr = [1, 2, 3]
          arr.tap { |a| a }
        RUBY
      end

      it "infers block parameter as Array type" do
        # Hover on "a" in the block - should be [Integer, Integer, Integer]
        expect_inferred_type(line: 2, column: 14, expected: "[Integer, Integer, Integer]")
      end
    end
  end

  describe "initialize method", :doc do
    context "User.new call result" do
      let(:source) do
        <<~RUBY
          class User
            def initialize(name)
              @name = name
            end
          end

          user = User.new("alice")
          user
        RUBY
      end

      it "→ User" do
        expect_inferred_type(line: 8, column: 0, expected: "User")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
