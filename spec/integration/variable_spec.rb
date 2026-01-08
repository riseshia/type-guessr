# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Variable Type Inference", :doc do
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

  describe "Instance variables" do
    context "instance variable in same class" do
      let(:source) do
        <<~RUBY
          class C
            def initialize(x)
              @x = 42
            end

            def foo(_)
              @x
            end
          end
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 7, column: 4, expected: "Integer")
      end
    end

    context "instance variable in subclass" do
      let(:source) do
        <<~RUBY
          class C
            def initialize(x)
              @x = 42
            end
          end

          class D < C
            def bar(_)
              @x
            end
          end
        RUBY
      end

      it "→ Integer" do
        expect_hover_type(line: 9, column: 6, expected: "Integer")
      end
    end

    context "instance variable type changes" do
      let(:source) do
        <<~RUBY
          class C
            def initialize(x)
              @x = "42"
            end

            def foo(_)
              @x
            end
          end
        RUBY
      end

      it "→ String" do
        expect_hover_type(line: 7, column: 4, expected: "String")
      end
    end
  end

  describe "Class variables" do
    context "class variable in method" do
      let(:source) do
        <<~RUBY
          class A
            def foo
              @@x = :ok
              @@x
            end
          end
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 4, column: 6, expected: "Symbol")
      end
    end

    context "class variable at class level" do
      let(:source) do
        <<~RUBY
          class B
            @@x = :ok

            def foo
              @@x
            end
          end
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 5, column: 6, expected: "Symbol")
      end
    end
  end

  describe "Multiple assignment" do
    context "simple multiple assignment" do
      let(:source) do
        <<~RUBY
          def baz
            [1, 1.0, "str"]
          end

          def foo
            x, y, z, w = baz
            x
          end
        RUBY
      end

      it "→ Integer (first element)" do
        pending "Not supported yet"
        expect_hover_type(line: 7, column: 2, expected: "Integer")
      end
    end

    context "multiple assignment in block" do
      let(:source) do
        <<~RUBY
          def baz
            [1, 1.0, "str"]
          end

          def bar
            x = nil
            1.times do |_|
              x, y, z, w = baz
            end
            x
          end
        RUBY
      end

      it "handles block assignment" do
        response = hover_on_source(source, { line: 9, character: 2 })
        expect(response).not_to be_nil
      end
    end
  end

  describe "Operator assignment" do
    context "||= assignment with nil" do
      let(:source) do
        <<~RUBY
          class C
            def get_lv
              lv = nil
              lv ||= :LVar
              lv
            end
          end
        RUBY
      end

      it "→ ?Symbol" do
        expect_hover_type(line: 5, column: 6, expected: "?Symbol")
      end
    end

    context "&&= assignment with value" do
      let(:source) do
        <<~RUBY
          class C
            def get_lv
              lv = :LVar0
              lv &&= :LVar
              lv
            end
          end
        RUBY
      end

      it "→ Symbol" do
        expect_hover_type(line: 5, column: 4, expected: "Symbol")
      end
    end
  end

  describe "Variable scope isolation" do
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
        response_a = hover_on_source(source, { line: 2, character: 15 })
        expect(response_a.contents.value).to include("untyped")

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

      it "→ String" do
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

      it "→ Recipe" do
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

      it "→ Recipe" do
        expect_hover_type(line: 3, column: 6, expected: "Recipe")
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

      it "→ Integer" do
        expect_hover_response(line: 4, column: 4)
      end
    end

    context "top-level variable" do
      let(:source) do
        <<~RUBY
          x = 42
          x
        RUBY
      end

      it "→ Integer" do
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

      it "→ String" do
        expect_hover_type(line: 5, column: 6, expected: "String")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
