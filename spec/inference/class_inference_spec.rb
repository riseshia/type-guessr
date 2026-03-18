# frozen_string_literal: true

require "spec_helper"
require "prism"
require "ruby_indexer/ruby_indexer"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Class Instance Type Inference", :doc do
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
        expect_inferred_type(line: 5, column: 3, expected: "User")
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
        expect_inferred_type(line: 7, column: 3, expected: "Admin::User")
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
        expect_inferred_type(line: 4, column: 3, expected: "User")
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
        expect_inferred_type(line: 10, column: 3, expected: "A::B::C::D")
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
        expect_inferred_type(line: 12, column: 0, expected: "C")
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
        expect_inferred_type(line: 7, column: 0, expected: "singleton(C)")
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
        expect_inferred_type(line: 9, column: 0, expected: "singleton(C)")
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
        expect_inferred_type(line: 17, column: 0, expected: "B")
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
        expect_inferred_type(line: 14, column: 0, expected: "Integer")
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
        expect_inferred_type(line: 11, column: 0, expected: "Integer")
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
        expect_inferred_signature(line: 6, column: 7, expected_signature: "(untyped a, untyped b) -> Recipe")
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
        expect_inferred_signature(line: 4, column: 6, expected_signature: "() -> Empty")
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
        expect_inferred_signature(line: 6, column: 7, expected_signature: "(untyped host, ?Integer port) -> Config")
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
        expect_inferred_signature(line: 3, column: 9, expected_signature: "() -> User")
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
        expect_inferred_signature(line: 6, column: 9, expected_signature: "(untyped name, untyped age) -> User")
      end
    end
  end

  describe "Singleton method definitions (def self.method)" do
    context "project singleton method signature" do
      let(:source) do
        <<~RUBY
          class Calculator
            def self.add(a, b)
              a + b
            end
          end
        RUBY
      end

      it "→ (untyped a, untyped b) -> untyped" do
        expect_inferred_signature(line: 2, column: 12, expected_signature: "(untyped a, untyped b)")
      end
    end
  end

  describe "module_function def" do
    context "module_function method has signature" do
      let(:source) do
        <<~RUBY
          module Config
            module_function def default_config
              { "enabled" => true }
            end
          end
        RUBY
      end

      it "→ () -> Hash[String, true]" do
        expect_inferred_signature(line: 2, column: 22, expected_signature: "() -> Hash[String, true]")
      end
    end

    context "internal bare call" do
      let(:source) do
        <<~RUBY
          module Config
            module_function def default_config
              { "enabled" => true }
            end

            def load
              config = default_config
              config
            end
          end
        RUBY
      end

      it "→ Hash[String, true]" do
        expect_inferred_type(line: 8, column: 8, expected: "Hash[String, true]")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
