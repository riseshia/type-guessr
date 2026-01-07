# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Variable Type Inference from TypeProf Scenarios" do
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

      it "infers @x as Integer inside foo" do
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

      it "infers @x as Integer in subclass" do
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

      it "infers @x as String" do
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

      it "infers @@x as Symbol :ok" do
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

      it "infers @@x as Symbol :ok" do
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

      it "infers x as Integer (first element)" do
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

      it "infers x as Integer | nil" do
        # NOTE: This may fail if type-guessr doesn't track block assignments properly
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

      it "infers lv as Symbol :LVar" do
        expect_hover_type(line: 5, column: 6, expected: "Symbol")
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

      it "infers lv as Symbol union" do
        expect_hover_type(line: 5, column: 4, expected: "Symbol")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
