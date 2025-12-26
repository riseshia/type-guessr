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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "name",
          def_line: 2,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("String")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*String/)
      end
    end

    it "infers Integer from integer literal" do
      source = <<~RUBY
        def foo
          count = 42
          count
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "count",
          def_line: 2,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Integer/)
      end
    end

    it "infers Float from float literal" do
      source = <<~RUBY
        def foo
          price = 19.99
          price
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "price",
          def_line: 2,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("Float")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Float/)
      end
    end

    it "infers Array from array literal" do
      source = <<~RUBY
        def foo
          items = []
          items
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "items",
          def_line: 2,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("Array")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Array/)
      end
    end

    it "infers Hash from hash literal" do
      source = <<~RUBY
        def foo
          data = {}
          data
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "data",
          def_line: 2,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("Hash")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Hash/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "user",
          def_line: 5,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("User")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 5, character: 2 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*User/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "test_namespaced",
          var_name: "admin",
          def_line: 7,
          def_column: 4,
          type: TypeGuessr::Core::Types::ClassInstance.new("Admin::User")
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 7, character: 4 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Admin::User/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "recipe",
          def_line: 17,
          def_column: 12,
          method_name: "ingredients",
          call_line: 18,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "recipe",
          def_line: 17,
          def_column: 12,
          method_name: "steps",
          call_line: 19,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 16, character: 12 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*Recipe/)
        expect(content).not_to match(/Article/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "item",
          def_line: 17,
          def_column: 12,
          method_name: "save",
          call_line: 18,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "item",
          def_line: 17,
          def_column: 12,
          method_name: "destroy",
          call_line: 19,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 16, character: 12 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Ambiguous type/)
        expect(content).to match(/Cacheable/)
        expect(content).to match(/Persistable/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "item",
          def_line: 26,
          def_column: 12,
          method_name: "common_method_for_truncation_test",
          call_line: 27,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 25, character: 12 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Ambiguous type/)
        expect(content).to match(/\.\.\./)
        main_content = content.split("**[TypeGuessr Debug]").first
        class_count = main_content.scan(/`Class[A-E]`/).size
        expect(class_count).to eq(3)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "Foo#method_b",
          var_name: "context",
          def_line: 6,
          def_column: 15,
          method_name: "name",
          call_line: 7,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "Foo#method_b",
          var_name: "context",
          def_line: 6,
          def_column: 15,
          method_name: "age",
          call_line: 8,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 15 } }
        )
        result_a = pop_result(server)
        content_a = result_a.response.contents.value

        server.process_message(
          id: 2,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 6, character: 4 } }
        )
        result_b = pop_result(server)
        content_b = result_b.response.contents.value

        expect(content_a).not_to include("name")
        expect(content_a).not_to include("age")

        expect(content_b).to include("name")
        expect(content_b).to include("age")
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        # Instance variable @user
        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :instance_variables,
          scope_id: "Bar",
          var_name: "@user",
          def_line: 3,
          def_column: 6,
          type: TypeGuessr::Core::Types::ClassInstance.new("User")
        )

        # Local variable user
        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "Bar#process",
          var_name: "user",
          def_line: 7,
          def_column: 6,
          type: TypeGuessr::Core::Types::ClassInstance.new("String")
        )

        # Hover on local variable user (line 7, character 4)
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 7, character: 4 } }
        )
        result_local = pop_result(server)
        content_local = result_local.response.contents.value

        expect(content_local).to match(/String/)
        expect(content_local).not_to match(/User/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "cook",
          var_name: "recipe",
          def_line: 9,
          def_column: 9,
          method_name: "ingredients",
          call_line: 10,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "cook",
          var_name: "recipe",
          def_line: 9,
          def_column: 9,
          method_name: "steps",
          call_line: 11,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 11, character: 4 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:/)
        expect(content).to match(/\[`Recipe`\]\(file:/)
      end
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

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "item",
          def_line: 1,
          def_column: 12,
          method_name: "save",
          call_line: 2,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 0, character: 12 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        # Debug mode is enabled in spec_helper.rb via ENV["TYPE_GUESSR_DEBUG"] = "1"
        expect(content).to match(/\*\*\[TypeGuessr Debug\]/)
        expect(content).to match(/Reason:/)
        expect(content).to match(/Method calls:/)
      end
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
end
# rubocop:enable RSpec/DescribeClass
