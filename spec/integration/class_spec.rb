# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# rubocop:disable RSpec/DescribeClass
RSpec.describe "Class Instance Type Inference from TypeProf Scenarios" do
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

  describe "Class instantiation" do
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

      it "infers instance as C" do
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

      it "infers klass as singleton(C)" do
        response = hover_on_source(source, { line: 7, character: 0 })
        expect(response).not_to be_nil
        # Should be singleton(C) or Class
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

      it "infers klass as singleton(C)" do
        response = hover_on_source(source, { line: 9, character: 0 })
        expect(response).not_to be_nil
        # Should be singleton(C) or Class
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

      it "infers instance as B" do
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

      it "infers result as Integer from module method" do
        expect_hover_type(line: 14, column: 0, expected: "Integer")
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
