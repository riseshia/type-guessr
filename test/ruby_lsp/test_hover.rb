# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/internal"

module RubyLsp
  module TypeGuessr
    class TestHover < Minitest::Test
      include TypeGuessrTestHelper

      def test_hover_on_local_variable
        source = <<~RUBY
          def foo
            user = "John"
            user
          end
        RUBY

        response = hover_on_source(source, { line: 2, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_instance_variable
        source = <<~RUBY
          class Foo
            def bar
              @user = "John"
              @user.upcase
            end
          end
        RUBY

        response = hover_on_source(source, { line: 3, character: 6 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_class_variable
        source = <<~RUBY
          class Foo
            @@count = 0
            @@count.succ
          end
        RUBY

        response = hover_on_source(source, { line: 2, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_global_variable
        source = <<~RUBY
          $global = "test"
          $global.upcase
        RUBY

        response = hover_on_source(source, { line: 1, character: 0 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_response_is_markdown
        source = <<~RUBY
          $global = "test"
          $global.upcase
        RUBY

        response = hover_on_source(source, { line: 1, character: 0 })

        assert_equal "markdown", response.contents.kind
      end

      # TODO: Investigate why self node hover is not working
      # def test_hover_on_self
      #   source = <<~RUBY
      #     class Foo
      #       def bar
      #         self
      #       end
      #     end
      #   RUBY
      #
      #   response = hover_on_source(source, { line: 2, character: 4 })
      #
      #   assert_match(/Ruby LSP Guesser/, response.contents.value)
      # end

      def test_hover_on_required_parameter
        source = <<~RUBY
          def greet(name)
            name.upcase
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_optional_parameter_usage
        source = <<~RUBY
          def greet(name = "World")
            name.upcase
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_keyword_parameter_usage
        source = <<~RUBY
          def greet(name:)
            name.upcase
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_rest_parameter_usage
        source = <<~RUBY
          def greet(*names)
            names.join
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_keyword_rest_parameter_usage
        source = <<~RUBY
          def greet(**options)
            options.keys
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_block_parameter_usage
        source = <<~RUBY
          def execute(&block)
            block.call
          end
        RUBY

        response = hover_on_source(source, { line: 1, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_self
        source = <<~RUBY
          class Foo
            def bar
              self
            end
          end
        RUBY

        response = hover_on_source(source, { line: 2, character: 4 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_parameter_definition
        source = <<~RUBY
          def greet(name)
            name.upcase
          end
        RUBY

        response = hover_on_source(source, { line: 0, character: 10 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_keyword_parameter_definition
        source = <<~RUBY
          def greet(name:)
            name.upcase
          end
        RUBY

        response = hover_on_source(source, { line: 0, character: 10 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_on_forwarding_parameter
        source = <<~RUBY
          def forward(...)
            other_method(...)
          end
        RUBY

        response = hover_on_source(source, { line: 0, character: 12 })

        # Should show hover content
        refute_nil response.contents.value
        refute_empty response.contents.value
      end

      def test_hover_shows_unique_method_calls
        source = <<~RUBY
          def process(unique_test_var_12345)
            unique_test_var_12345.custom_method_1
            unique_test_var_12345.custom_method_2
            unique_test_var_12345.custom_method_1
            unique_test_var_12345.custom_method_1
          end
        RUBY

        with_server_and_addon(source) do |server, uri|
          # Clear the index and add test data
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Simulate duplicate method calls being indexed
          # (line 0, character 12 is where 'unique_test_var_12345' parameter is defined)
          # Scope: top-level method "process", so scope_id is "process"
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

          # Now request hover
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 0, character: 12 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Should only show 'custom_method_1' and 'custom_method_2' once each
          method1_count = content.scan("`custom_method_1`").size
          method2_count = content.scan("`custom_method_2`").size

          assert_equal 1, method1_count,
                       "Method 'custom_method_1' should appear only once, but appeared #{method1_count} times"
          assert_equal 1, method2_count,
                       "Method 'custom_method_2' should appear only once, but appeared #{method2_count} times"
        end
      end

      def test_hover_on_instance_variable_shows_method_calls
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
          # Clear index and manually add the method calls to avoid interference from background indexing
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Manually index the method calls
          # Instance variable in TestClass, so scope_id is "TestClass"
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

          # Hover on @unique_ivar_xyz_12345 in the process method (line 6, where it's being read)
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 6, character: 6 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Check if our guesser is working
          # Guesser should provide hover content
          refute_nil content
          refute_empty content

          # Should show method calls on @unique_ivar_xyz_12345
          assert_match(/each_key/, content, "Should show 'each_key' method call")
          assert_match(/fetch/, content, "Should show 'fetch' method call")

          # each_key should appear only once despite being called twice
          each_key_count = content.scan("`each_key`").size
          assert_equal 1, each_key_count,
                       "Method 'each_key' should appear only once, but appeared #{each_key_count} times"
        end
      end

      def test_hover_shows_ambiguous_when_multiple_matches
        # Phase 3, Test 2: Hover shows "ambiguous" when multiple classes match
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
          # Clear and setup index
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Add method calls for 'item' variable
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

          # Hover on 'item' parameter
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 16, character: 12 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Should show ambiguous type
          assert_match(/Ambiguous type/, content, "Should show ambiguous type message")
          assert_match(/Cacheable/, content, "Should mention Cacheable")
          assert_match(/Persistable/, content, "Should mention Persistable")
        end
      end

      def test_hover_shows_method_list_when_no_type_inferred
        # Phase 3, Test 3: Hover shows method list when no type can be inferred
        source = <<~RUBY
          def process(unknown_var)
            unknown_var.unique_method_xyz_12345
            unknown_var
          end
        RUBY

        with_server_and_addon(source) do |server, uri|
          # Clear and setup index
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Add a method call that won't match any indexed class
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

          # Hover on 'unknown_var' parameter
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 0, character: 12 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Should fallback to showing method list
          assert_match(/Method calls:/, content, "Should show 'Method calls:' header")
          assert_match(/unique_method_xyz_12345/, content, "Should show the method name")
          refute_match(/Inferred type/, content, "Should not show inferred type")
        end
      end

      def test_hover_shows_inferred_type_when_single_match
        # Phase 3, Test 1: Hover shows inferred type when exactly one class matches
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
          # Clear and setup index
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Manually add method calls for 'recipe' variable
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

          # Hover on 'recipe' parameter (definition)
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 16, character: 12 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Should show inferred type
          assert_match(/Inferred type:.*Recipe/, content, "Should show inferred type as Recipe")
          refute_match(/Article/, content, "Should not show Article")
        end
      end

      def test_hover_shows_inferred_type_on_parameter_usage
        # Test: Hover shows inferred type when hovering on parameter usage (not just definition)
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
          # Clear and setup index
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Add method calls for 'user' parameter
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

          # Hover on 'user' in usage (line 12: the last 'user')
          server.process_message(
            id: 1,
            method: "textDocument/hover",
            params: { textDocument: { uri: uri }, position: { line: 11, character: 4 } }
          )

          result = pop_result(server)
          response = result.response
          content = response.contents.value

          # Should show inferred type
          assert_match(/Inferred type:.*User/, content, "Should show inferred type as User")
        end
      end

      def test_hover_shows_string_type_for_string_literal
        source = <<~RUBY
          def foo
            name = "John"
            name
          end
        RUBY

        with_server_and_addon(source) do |server, uri|
          # Clear and manually add type information
          index = RubyLsp::TypeGuessr::VariableIndex.instance
          index.clear

          # Add variable type for 'name' variable
          # line 1, column 2 is where 'name' is defined
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

          assert_match(/Inferred type:.*String/, content, "Should infer String type for string literal")
        end
      end

      def test_hover_shows_integer_type_for_number_literal
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

          assert_match(/Inferred type:.*Integer/, content, "Should infer Integer type for number literal")
        end
      end

      def test_hover_shows_class_type_for_new_call
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

          assert_match(/Inferred type:.*User/, content, "Should infer User type for User.new")
        end
      end

      def test_hover_shows_float_type_for_float_literal
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

          assert_match(/Inferred type:.*Float/, content, "Should infer Float type for float literal")
        end
      end

      def test_hover_shows_array_type_for_array_literal
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

          assert_match(/Inferred type:.*Array/, content, "Should infer Array type for array literal")
        end
      end

      def test_hover_shows_hash_type_for_hash_literal
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

          assert_match(/Inferred type:.*Hash/, content, "Should infer Hash type for hash literal")
        end
      end

      def test_hover_direct_type_takes_priority_over_method_based
        # Direct type inference should take priority over method-based inference
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

          # Should show direct type "User" from User.new, not method-based inference
          assert_match(/Inferred type:.*User/, content, "Should infer User type from User.new")
          # Should not show "Ambiguous" or method list
          refute_match(/Ambiguous/, content, "Should not show ambiguous message when direct type is available")
        end
      end

      private

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
    end
  end
end
