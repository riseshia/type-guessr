# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

RSpec.describe RubyLsp::TypeGuessr::Hover do
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

  describe "basic hover functionality" do
    it "shows hover content on local variable" do
      source = <<~RUBY
        def foo
          user = "John"
          user
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover content on instance variable" do
      source = <<~RUBY
        class Foo
          def bar
            @user = "John"
            @user.upcase
          end
        end
      RUBY

      response = hover_on_source(source, { line: 3, character: 6 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover content on class variable" do
      source = <<~RUBY
        class Foo
          @@count = 0
          @@count.succ
        end
      RUBY

      response = hover_on_source(source, { line: 2, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover content on global variable" do
      source = <<~RUBY
        $global = "test"
        $global.upcase
      RUBY

      response = hover_on_source(source, { line: 1, character: 0 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "returns markdown format" do
      source = <<~RUBY
        $global = "test"
        $global.upcase
      RUBY

      response = hover_on_source(source, { line: 1, character: 0 })

      expect(response.contents.kind).to eq("markdown")
    end
  end

  describe "parameter hover" do
    it "shows hover on required parameter usage" do
      source = <<~RUBY
        def greet(name)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on optional parameter usage" do
      source = <<~RUBY
        def greet(name = "World")
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on keyword parameter usage" do
      source = <<~RUBY
        def greet(name:)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on rest parameter usage" do
      source = <<~RUBY
        def greet(*names)
          names.join
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on keyword rest parameter usage" do
      source = <<~RUBY
        def greet(**options)
          options.keys
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on block parameter usage" do
      source = <<~RUBY
        def execute(&block)
          block.call
        end
      RUBY

      response = hover_on_source(source, { line: 1, character: 4 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on parameter definition" do
      source = <<~RUBY
        def greet(name)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 0, character: 10 })

      expect(response.contents.value).not_to be_nil
      expect(response.contents.value).not_to be_empty
    end

    it "shows hover on keyword parameter definition" do
      source = <<~RUBY
        def greet(name:)
          name.upcase
        end
      RUBY

      response = hover_on_source(source, { line: 0, character: 10 })

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

  describe "self hover" do
    it "shows hover content on self" do
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
  end

  describe "method call deduplication" do
    it "shows unique method calls only" do
      source = <<~RUBY
        def process(unique_test_var_12345)
          unique_test_var_12345.custom_method_1
          unique_test_var_12345.custom_method_2
          unique_test_var_12345.custom_method_1
          unique_test_var_12345.custom_method_1
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        # Simulate duplicate method calls being indexed
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "unique_test_var_12345",
          def_line: 1,
          def_column: 12,
          method_name: "custom_method_1",
          call_line: 2,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "unique_test_var_12345",
          def_line: 1,
          def_column: 12,
          method_name: "custom_method_2",
          call_line: 3,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "unique_test_var_12345",
          def_line: 1,
          def_column: 12,
          method_name: "custom_method_1",
          call_line: 4,
          call_column: 4
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "unique_test_var_12345",
          def_line: 1,
          def_column: 12,
          method_name: "custom_method_1",
          call_line: 5,
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

        method1_count = content.scan("`custom_method_1`").size
        method2_count = content.scan("`custom_method_2`").size

        expect(method1_count).to eq(1)
        expect(method2_count).to eq(1)
      end
    end

    it "shows unique method calls on instance variables" do
      source = <<~RUBY
        class TestClass
          def initialize
            @unique_ivar_xyz_12345 = {}
          end

          def process
            @unique_ivar_xyz_12345.each_key
            @unique_ivar_xyz_12345.fetch(:key)
            @unique_ivar_xyz_12345.each_key
          end
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :instance_variables,
          scope_id: "TestClass",
          var_name: "@unique_ivar_xyz_12345",
          def_line: 3,
          def_column: 6,
          method_name: "each_key",
          call_line: 7,
          call_column: 6
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :instance_variables,
          scope_id: "TestClass",
          var_name: "@unique_ivar_xyz_12345",
          def_line: 3,
          def_column: 6,
          method_name: "fetch",
          call_line: 8,
          call_column: 6
        )
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :instance_variables,
          scope_id: "TestClass",
          var_name: "@unique_ivar_xyz_12345",
          def_line: 3,
          def_column: 6,
          method_name: "each_key",
          call_line: 9,
          call_column: 6
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 6, character: 6 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).not_to be_nil
        expect(content).not_to be_empty
        expect(content).to match(/each_key/)
        expect(content).to match(/fetch/)

        each_key_count = content.scan("`each_key`").size
        expect(each_key_count).to eq(1)
      end
    end
  end

  describe "type inference display" do
    context "when multiple classes match (ambiguous)" do
      it "shows ambiguous type message" do
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
    end

    context "when too many classes match (truncated ambiguous)" do
      it "shows truncated type list with ellipsis" do
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
          # Should show only 3 classes plus ellipsis
          expect(content).to match(/\.\.\./)
          # Should have exactly 3 class names shown in the main content
          # (may have more in debug info section, so match only the first occurrence before debug section)
          main_content = content.split("**[TypeGuessr Debug]").first
          class_count = main_content.scan(/`Class[A-E]`/).size
          expect(class_count).to eq(3)
        end
      end
    end

    context "when no type can be guessed" do
      it "shows method list" do
        source = <<~RUBY
          def process(unknown_var)
            unknown_var.unique_method_xyz_12345
            unknown_var
          end
        RUBY

        with_server_and_addon(source) do |server, uri|
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          index.add_method_call(
            file_path: uri.to_s,
            scope_type: :local_variables,
            scope_id: "process",
            var_name: "unknown_var",
            def_line: 1,
            def_column: 12,
            method_name: "unique_method_xyz_12345",
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

          expect(content).to match(/Method calls:/)
          expect(content).to match(/unique_method_xyz_12345/)
          expect(content).not_to match(/Guessed type/)
        end
      end
    end

    context "when exactly one class matches" do
      it "shows guessed type" do
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

      it "shows guessed type on parameter usage" do
        source = <<~RUBY
          class User
            def save
            end

            def validate
            end
          end

          def register(user)
            user.validate
            user.save
            user
          end
        RUBY

        with_server_and_addon(source) do |server, uri|
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          index.add_method_call(
            file_path: uri.to_s,
            scope_type: :local_variables,
            scope_id: "register",
            var_name: "user",
            def_line: 9,
            def_column: 13,
            method_name: "validate",
            call_line: 10,
            call_column: 4
          )
          index.add_method_call(
            file_path: uri.to_s,
            scope_type: :local_variables,
            scope_id: "register",
            var_name: "user",
            def_line: 9,
            def_column: 13,
            method_name: "save",
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

          expect(content).to match(/Guessed type:.*User/)
        end
      end
    end
  end

  describe "literal type inference" do
    it "shows String type for string literal" do
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
          type: "String"
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

    it "shows Integer type for number literal" do
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
          type: "Integer"
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

    it "shows class type for .new call" do
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
          type: "User"
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

    it "shows Float type for float literal" do
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
          type: "Float"
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

    it "shows Array type for array literal" do
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
          type: "Array"
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

    it "shows Hash type for hash literal" do
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
          type: "Hash"
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

  describe "type inference priority" do
    it "prioritizes direct type over method-based inference" do
      source = <<~RUBY
        class User
          def save
          end
        end

        def process
          user = User.new
          user.save
          user
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        index = RubyLsp::TypeGuessr::VariableIndex.instance
        index.clear

        # Add direct type for user variable
        index.add_variable_type(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "user",
          def_line: 7,
          def_column: 4,
          type: "User"
        )

        # Also add method call (to test that direct type takes priority)
        index.add_method_call(
          file_path: uri.to_s,
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "user",
          def_line: 7,
          def_column: 4,
          method_name: "save",
          call_line: 8,
          call_column: 4
        )

        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 8, character: 4 } }
        )

        result = pop_result(server)
        response = result.response
        content = response.contents.value

        expect(content).to match(/Guessed type:.*User/)
        expect(content).not_to match(/Ambiguous/)
      end
    end
  end

  describe "scope isolation for local variables" do
    it "does not leak method calls from other methods with same parameter name" do
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

        # Index method calls for method_b's context only
        # method_a's context has no method calls
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

        # Hover on context in method_a (line 2 = @ctx = context, character 15 = context)
        server.process_message(
          id: 1,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 2, character: 15 } }
        )
        result_a = pop_result(server)
        content_a = result_a.response.contents.value

        # Hover on context in method_b (line 6 = context.name, character 4 = context)
        server.process_message(
          id: 2,
          method: "textDocument/hover",
          params: { textDocument: { uri: uri }, position: { line: 6, character: 4 } }
        )
        result_b = pop_result(server)
        content_b = result_b.response.contents.value

        # method_a's context should NOT show method calls from method_b
        expect(content_a).not_to include("name")
        expect(content_a).not_to include("age")

        # method_b's context should show its own method calls
        expect(content_b).to include("name")
        expect(content_b).to include("age")
      end
    end
  end

  describe "type definition links" do
    it "includes link to class definition in guessed type" do
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

        # Should include the type name with link format
        expect(content).to match(/Guessed type:/)
        expect(content).to match(/\[`Recipe`\]\(file:/)
      end
    end
  end
end
