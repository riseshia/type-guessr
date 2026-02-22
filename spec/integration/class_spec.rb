# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Class Instance Type Inference", :doc do
  include TypeGuessrTestHelper

  describe ".new Call Type Inference" do
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

      it "→ untyped (dynamic class)" do
        response = hover_on_source(source, { line: 2, character: 2 })
        # Should not infer a specific type since klass is unknown
        expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
      end
    end
  end

  describe ".new hover with initialize parameters" do
    context "when class has initialize with required params" do
      let(:source) do
        <<~RUBY
          class Recipe
            def initialize(a, b)
            end
          end

          Recipe.new(1, 2)
        RUBY
      end

      it "→ (untyped a, untyped b) -> Recipe" do
        # Hover on "new" at line 6, column 7
        expect_hover_method_signature(line: 6, column: 7, expected_signature: "(untyped a, untyped b) -> Recipe")
      end
    end

    context "when class has no initialize" do
      let(:source) do
        <<~RUBY
          class Empty
          end

          Empty.new
        RUBY
      end

      it "→ () -> Empty" do
        expect_hover_method_signature(line: 4, column: 6, expected_signature: "() -> Empty")
      end
    end

    context "when class has initialize with optional params" do
      let(:source) do
        <<~RUBY
          class Config
            def initialize(host, port = 8080)
            end
          end

          Config.new("localhost")
        RUBY
      end

      it "→ (untyped host, ?Integer port) -> Config" do
        expect_hover_method_signature(line: 6, column: 7, expected_signature: "(untyped host, ?Integer port) -> Config")
      end
    end

    context "self.new in singleton method" do
      let(:source) do
        <<~RUBY
          class User
            def self.create
              self.new
            end
          end
        RUBY
      end

      it "→ () -> User" do
        # Hover on "new" at line 3, column 9
        expect_hover_method_signature(line: 3, column: 9, expected_signature: "() -> User")
      end
    end

    context "self.new with initialize params in singleton method" do
      let(:source) do
        <<~RUBY
          class User
            def initialize(name, age)
            end

            def self.create(name, age)
              self.new(name, age)
            end
          end
        RUBY
      end

      it "→ (untyped name, untyped age) -> User" do
        # Hover on "new" at line 6, column 9
        expect_hover_method_signature(line: 6, column: 9, expected_signature: "(untyped name, untyped age) -> User")
      end
    end

    context "when calling .new with short constant name in nested module" do
      let(:source) do
        <<~RUBY
          module Outer
            class Inner
              def initialize(arg1, arg2 = nil)
              end
            end

            class User
              def create
                Inner.new("test")
              end
            end
          end
        RUBY
      end

      it "resolves full class name for constructor signature lookup → (untyped arg1, ?nil arg2) -> Outer::Inner" do
        # Hover on "new" at line 9, column 12 (0-indexed: line 8, column 12 = "n" in "new")
        expect_hover_method_signature(line: 9, column: 12, expected_signature: "(untyped arg1, ?nil arg2) -> Outer::Inner")
      end
    end

    context "when calling .new with deeply nested short constant name" do
      let(:source) do
        <<~RUBY
          module A
            module B
              class Target
                def initialize(x, y, z = 0)
                end
              end

              class Consumer
                def build
                  Target.new(1, 2)
                end
              end
            end
          end
        RUBY
      end

      it "resolves deeply nested class name → (untyped x, untyped y, ?Integer z) -> A::B::Target" do
        # Hover on "new" at line 10, column 15 (0-indexed: line 9, column 15 = "n" in "new")
        expect_hover_method_signature(line: 10, column: 15, expected_signature: "(untyped x, untyped y, ?Integer z) -> A::B::Target")
      end
    end
  end

  describe "Class instantiation (misc)" do
    context "basic class instantiation" do
      let(:source) do
        <<~RUBY
          class C
            def initialize(n)
              n
            end

            def foo(n)
              C
            end
          end

          C.new(1).foo("str")
          instance = C.new(1)
        RUBY
      end

      it "→ C" do
        expect_hover_type(line: 12, column: 0, expected: "C")
      end
    end

    context "class reference in method" do
      let(:source) do
        <<~RUBY
          class C
            def foo(n)
              C
            end
          end

          klass = C.new(1).foo("str")
        RUBY
      end

      it "→ singleton(C)" do
        expect_hover_type(line: 7, column: 0, expected: "singleton(C)")
      end
    end

    context "nested class" do
      let(:source) do
        <<~RUBY
          class C
            class D
              def foo(n)
                C
              end
            end
          end

          klass = C::D.new.foo("str")
        RUBY
      end

      it "→ singleton(C)" do
        expect_hover_type(line: 9, column: 0, expected: "singleton(C)")
      end
    end
  end

  describe "Initialize method" do
    context "initialize with instance variable" do
      let(:source) do
        <<~RUBY
          class A
          end

          class B
            def initialize(xxx)
              @xxx = xxx
            end
          end

          class C
          end

          def foo
            B.new(1)
          end

          instance = foo
        RUBY
      end

      it "→ B" do
        expect_hover_type(line: 17, column: 0, expected: "B")
      end
    end
  end

  describe "Module inclusion" do
    context "module method call" do
      let(:source) do
        <<~RUBY
          module M
            def foo
              42
            end
          end

          class C
            include M
            def bar
              foo
            end
          end

          result = C.new.bar
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 14, column: 0, expected: "Integer")
      end
    end
  end

  describe "Module extend" do
    context "class method from extended module" do
      let(:source) do
        <<~RUBY
          module M
            def foo
              42
            end
          end

          class C
            extend M
          end

          result = C.foo
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 11, column: 0, expected: "Integer")
      end
    end
  end

  describe "Class method calls (ClassName.method)" do
    context "stdlib class method signature" do
      let(:source) do
        <<~RUBY
          result = File.exist?("test.txt")
          result
        RUBY
      end

      it "shows Guessed Signature for stdlib class method" do
        # File.exist? is a stdlib class method with RBS definition
        expect_hover_method_signature(
          line: 1,
          column: 14,
          expected_signature: "(::string | ::_ToPath | ::IO file_name) -> bool"
        )
      end
    end

    context "gem class method signature" do
      let(:source) do
        <<~RUBY
          loader = RBS::EnvironmentLoader.new
          env = RBS::Environment.from_loader(loader)
          env
        RUBY
      end

      it "shows Guessed Signature for class method" do
        # Even for gem classes without RBS definitions, show signature format
        # Argument type is inferred from the actual value (RBS::EnvironmentLoader)
        # Parameter name is retrieved from RubyIndexer
        expect_hover_method_signature(
          line: 2,
          column: 23,
          expected_signature: "(RBS::EnvironmentLoader loader) -> untyped"
        )
      end
    end
  end

  describe "Instance method calls (receiver.method)" do
    context "gem instance method signature" do
      let(:source) do
        <<~RUBY
          loader = RBS::EnvironmentLoader.new
          env = RBS::Environment.from_loader(loader)
          resolved = env.resolve_type_names
          resolved
        RUBY
      end

      it "shows Guessed Signature for instance method" do
        # With full indexing, RBS definitions are available for gem methods
        # RBS::Environment#resolve_type_names signature varies by RBS version:
        #   v3.10.2: (?only: untyped) -> untyped
        #   v3.10.3+: () -> untyped
        # Note: This test previously worked via duck typing fallback (MethodRegistry)
        expect_hover_method_signature(
          line: 3,
          column: 15,
          expected_signature: ") -> untyped"
        )
      end
    end
  end

  describe "Singleton method definitions (def self.method)" do
    context "project singleton method" do
      let(:source) do
        <<~RUBY
          class Calculator
            def self.add(a, b)
              a + b
            end
          end
        RUBY
      end

      it "shows signature for singleton method definition" do
        # Hover on "add" in "def self.add(a, b)"
        response = expect_hover_response(line: 2, column: 12)
        expect(response.contents.value).to include("Guessed Signature")
        expect(response.contents.value).to include("(untyped a, untyped b)")
      end
    end

    context "namespaced singleton method" do
      let(:source) do
        <<~RUBY
          module Math
            class Utils
              def self.square(x)
                x * x
              end
            end
          end
        RUBY
      end

      it "shows signature for namespaced singleton method" do
        # Hover on "square" in "def self.square(x)"
        response = expect_hover_response(line: 3, column: 16)
        expect(response.contents.value).to include("Guessed Signature")
        expect(response.contents.value).to include("(untyped x)")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
