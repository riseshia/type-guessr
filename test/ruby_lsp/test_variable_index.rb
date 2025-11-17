# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module TypeGuessr
    class TestVariableIndex < Minitest::Test
      def setup
        @index = VariableIndex.instance
        @index.clear
      end

      def test_add_and_retrieve_method_call
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )

        assert_equal 1, calls.size
        assert_equal "name", calls[0][:method]
        assert_equal 2, calls[0][:line]
        assert_equal 0, calls[0][:column]
      end

      def test_multiple_method_calls_same_variable
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "email",
          call_line: 3,
          call_column: 0
        )

        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )

        assert_equal 2, calls.size
        assert_equal "name", calls[0][:method]
        assert_equal "email", calls[1][:method]
      end

      def test_different_variables_with_same_name_different_locations
        # First variable: user at line 1
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        # Second variable: user at line 10 (different scope)
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "user",
          def_line: 10,
          def_column: 0,
          method_name: "email",
          call_line: 11,
          call_column: 0
        )

        calls1 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )

        calls2 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "user",
          def_line: 10,
          def_column: 0
        )

        assert_equal 1, calls1.size
        assert_equal "name", calls1[0][:method]

        assert_equal 1, calls2.size
        assert_equal "email", calls2[0][:method]
      end

      def test_no_duplicate_method_calls
        2.times do
          @index.add_method_call(
            file_path: "/test/file.rb",
            scope_type: :local_variables,
            scope_id: "test_method",
            var_name: "user",
            def_line: 1,
            def_column: 0,
            method_name: "name",
            call_line: 2,
            call_column: 0
          )
        end

        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )

        assert_equal 1, calls.size
      end

      def test_clear_index
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        assert @index.size.positive?

        @index.clear
        assert_equal 0, @index.size
      end

      def test_nonexistent_variable_returns_empty_array
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "test_method",
          var_name: "nonexistent",
          def_line: 1,
          def_column: 0
        )

        assert_equal [], calls
      end

      def test_clear_file_removes_only_specified_file
        # Add method calls for first file
        @index.add_method_call(
          file_path: "/test/file1.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        # Add method calls for second file
        @index.add_method_call(
          file_path: "/test/file2.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "post",
          def_line: 1,
          def_column: 0,
          method_name: "title",
          call_line: 2,
          call_column: 0
        )

        assert @index.size.positive?

        # Clear only first file
        @index.clear_file("/test/file1.rb")

        # First file should be cleared
        calls1 = @index.get_method_calls(
          file_path: "/test/file1.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )
        assert_equal [], calls1

        # Second file should remain
        calls2 = @index.get_method_calls(
          file_path: "/test/file2.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "post",
          def_line: 1,
          def_column: 0
        )
        assert_equal 1, calls2.size
        assert_equal "title", calls2[0][:method]
      end

      def test_clear_file_with_multiple_variables
        # Add multiple variables in the same file
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0,
          method_name: "name",
          call_line: 2,
          call_column: 0
        )

        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "post",
          def_line: 5,
          def_column: 0,
          method_name: "title",
          call_line: 6,
          call_column: 0
        )

        assert @index.size.positive?

        # Clear the file
        @index.clear_file("/test/file.rb")

        # All variables from the file should be cleared
        assert_equal 0, @index.size

        calls1 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method1",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )
        assert_equal [], calls1

        calls2 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "method2",
          var_name: "post",
          def_line: 5,
          def_column: 0
        )
        assert_equal [], calls2
      end

      def test_instance_variable_scope_isolation
        # Same variable name in different classes should be separate
        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "Recipe",
          var_name: "@index",
          def_line: 3,
          def_column: 4,
          method_name: "increment",
          call_line: 10,
          call_column: 4
        )

        @index.add_method_call(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "Database",
          var_name: "@index",
          def_line: 20,
          def_column: 4,
          method_name: "fetch",
          call_line: 25,
          call_column: 4
        )

        recipe_calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "Recipe",
          var_name: "@index",
          def_line: 3,
          def_column: 4
        )

        database_calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "Database",
          var_name: "@index",
          def_line: 20,
          def_column: 4
        )

        assert_equal 1, recipe_calls.size
        assert_equal "increment", recipe_calls[0][:method]

        assert_equal 1, database_calls.size
        assert_equal "fetch", database_calls[0][:method]
      end

      def test_find_definitions_with_filters
        # Add variables in different scopes
        @index.add_method_call(
          file_path: "/test/file1.rb",
          scope_type: :instance_variables,
          scope_id: "Recipe",
          var_name: "@user",
          def_line: 5,
          def_column: 4,
          method_name: "name",
          call_line: 10,
          call_column: 4
        )

        @index.add_method_call(
          file_path: "/test/file2.rb",
          scope_type: :local_variables,
          scope_id: "process",
          var_name: "@user",
          def_line: 2,
          def_column: 2,
          method_name: "email",
          call_line: 5,
          call_column: 2
        )

        # Find all @user definitions
        all_defs = @index.find_definitions(var_name: "@user")
        assert_equal 2, all_defs.size

        # Find only instance variable @user
        ivar_defs = @index.find_definitions(var_name: "@user", scope_type: :instance_variables)
        assert_equal 1, ivar_defs.size
        assert_equal "Recipe", ivar_defs[0][:scope_id]

        # Find only in specific file
        file1_defs = @index.find_definitions(var_name: "@user", file_path: "/test/file1.rb")
        assert_equal 1, file1_defs.size
        assert_equal "/test/file1.rb", file1_defs[0][:file_path]
      end

      def test_find_variable_type_at_location_with_exact_scope
        # Add type information for a variable
        @index.add_variable_type(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Recipe#cook",
          var_name: "user",
          def_line: 5,
          def_column: 2,
          type: "User"
        )

        # Find type at location after definition
        type = @index.find_variable_type_at_location(
          var_name: "user",
          scope_type: :local_variables,
          max_line: 10,
          scope_id: "Recipe#cook"
        )

        assert_equal "User", type
      end

      def test_find_variable_type_at_location_before_definition_returns_nil
        @index.add_variable_type(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Recipe#cook",
          var_name: "user",
          def_line: 5,
          def_column: 2,
          type: "User"
        )

        # Try to find type before definition line
        type = @index.find_variable_type_at_location(
          var_name: "user",
          scope_type: :local_variables,
          max_line: 3,
          scope_id: "Recipe#cook"
        )

        assert_nil type
      end

      def test_find_variable_type_at_location_finds_closest_definition
        # Add multiple definitions at different lines
        @index.add_variable_type(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Recipe#cook",
          var_name: "item",
          def_line: 5,
          def_column: 2,
          type: "String"
        )

        @index.add_variable_type(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Recipe#cook",
          var_name: "item",
          def_line: 10,
          def_column: 2,
          type: "Integer"
        )

        # At line 8, should find the first definition (String)
        type1 = @index.find_variable_type_at_location(
          var_name: "item",
          scope_type: :local_variables,
          max_line: 8,
          scope_id: "Recipe#cook"
        )
        assert_equal "String", type1

        # At line 15, should find the second definition (Integer)
        type2 = @index.find_variable_type_at_location(
          var_name: "item",
          scope_type: :local_variables,
          max_line: 15,
          scope_id: "Recipe#cook"
        )
        assert_equal "Integer", type2
      end

      def test_find_variable_type_at_location_without_scope_id_searches_broadly
        @index.add_variable_type(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Recipe#cook",
          var_name: "user",
          def_line: 5,
          def_column: 2,
          type: "User"
        )

        # Search without specifying scope_id - should still find it
        type = @index.find_variable_type_at_location(
          var_name: "user",
          scope_type: :local_variables,
          max_line: 10
        )

        assert_equal "User", type
      end

      def test_find_variable_type_at_location_nonexistent_returns_nil
        type = @index.find_variable_type_at_location(
          var_name: "nonexistent",
          scope_type: :local_variables,
          max_line: 10,
          scope_id: "Recipe#cook"
        )

        assert_nil type
      end
    end
  end
end
