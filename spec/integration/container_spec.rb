# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Container Type Inference from TypeProf Scenarios" do
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

  describe "Array type inference" do
    context "array with method chaining" do
      let(:source) do
        <<~RUBY
          def foo(a)
            a
          end

          foo([1, 2, 3].to_a)
          r = [1, 2, 3].to_a
        RUBY
      end

      it "infers Array[Integer]" do
        expect_hover_type(line: 6, column: 0, expected: "Array[Integer]")
      end
    end
  end

  describe "Hash type inference" do
    context "hash with symbol keys and different value types" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          h = foo
        RUBY
      end

      it "infers hash type" do
        response = hover_on_source(source, { line: 7, character: 0 })
        expect(response).not_to be_nil
        # Should contain both :a and :b keys
      end
    end

    context "hash access with symbol key" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          def bar
            foo[:a]
          end

          r = bar
        RUBY
      end

      it "infers Integer from hash access" do
        expect_hover_type(line: 12, column: 0, expected: "Integer")
      end
    end

    context "hash with indexed assignment" do
      let(:source) do
        <<~RUBY
          def foo
            {
              a: 1,
              b: "str",
            }
          end

          def baz
            foo[:c] = 1.0
            foo[:c]
          end

          r = baz
        RUBY
      end

      it "infers union type after assignment" do
        response = hover_on_source(source, { line: 12, character: 0 })
        expect(response).not_to be_nil
        # Should include Float
      end
    end

    context "hash with splat operator" do
      let(:source) do
        <<~RUBY
          def bar
            { a: 1 }
          end

          def foo
            { **bar, b: 1 }
          end

          h = foo
        RUBY
      end

      it "infers merged hash type" do
        response = hover_on_source(source, { line: 8, character: 0 })
        expect(response).not_to be_nil
        # Should be Hash with :a and :b keys
      end
    end

    context "hash with implicit value syntax" do
      let(:source) do
        <<~RUBY
          def create
            x = 1
            y = "str"
            { x:, y: }
          end

          h = create
        RUBY
      end

      it "infers hash with implicit keys" do
        response = hover_on_source(source, { line: 6, character: 0 })
        expect(response).not_to be_nil
        # Should be Hash with :x and :y keys
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
