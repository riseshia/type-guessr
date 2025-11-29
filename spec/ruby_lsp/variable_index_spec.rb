# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyLsp::TypeGuessr::VariableIndex do
  subject(:index) { described_class.instance }

  before do
    index.clear
  end

  describe "#add_method_call and #get_method_calls" do
    it "adds and retrieves a method call" do
      index.add_method_call(
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

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "test_method",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("name")
      expect(calls[0][:line]).to eq(2)
      expect(calls[0][:column]).to eq(0)
    end

    it "handles multiple method calls on the same variable" do
      index.add_method_call(
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

      index.add_method_call(
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

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "test_method",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )

      expect(calls.size).to eq(2)
      expect(calls[0][:method]).to eq("name")
      expect(calls[1][:method]).to eq("email")
    end

    it "separates variables with same name in different scopes" do
      # First variable: user at line 1
      index.add_method_call(
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
      index.add_method_call(
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

      calls1 = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "method1",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )

      calls2 = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "method2",
        var_name: "user",
        def_line: 10,
        def_column: 0
      )

      expect(calls1.size).to eq(1)
      expect(calls1[0][:method]).to eq("name")

      expect(calls2.size).to eq(1)
      expect(calls2[0][:method]).to eq("email")
    end

    it "does not add duplicate method calls" do
      2.times do
        index.add_method_call(
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

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "test_method",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )

      expect(calls.size).to eq(1)
    end

    it "returns empty array for nonexistent variable" do
      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "test_method",
        var_name: "nonexistent",
        def_line: 1,
        def_column: 0
      )

      expect(calls).to eq([])
    end
  end

  describe "#clear" do
    it "clears all entries" do
      index.add_method_call(
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

      expect(index.size).to be_positive

      index.clear
      expect(index.size).to eq(0)
    end
  end

  describe "#clear_file" do
    it "removes only entries from the specified file" do
      # Add method calls for first file
      index.add_method_call(
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
      index.add_method_call(
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

      expect(index.size).to be_positive

      # Clear only first file
      index.clear_file("/test/file1.rb")

      # First file should be cleared
      calls1 = index.get_method_calls(
        file_path: "/test/file1.rb",
        scope_type: :local_variables,
        scope_id: "method1",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )
      expect(calls1).to eq([])

      # Second file should remain
      calls2 = index.get_method_calls(
        file_path: "/test/file2.rb",
        scope_type: :local_variables,
        scope_id: "method2",
        var_name: "post",
        def_line: 1,
        def_column: 0
      )
      expect(calls2.size).to eq(1)
      expect(calls2[0][:method]).to eq("title")
    end

    it "clears all variables in the file" do
      # Add multiple variables in the same file
      index.add_method_call(
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

      index.add_method_call(
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

      expect(index.size).to be_positive

      # Clear the file
      index.clear_file("/test/file.rb")

      # All variables from the file should be cleared
      expect(index.size).to eq(0)
    end
  end

  describe "instance variable scope isolation" do
    it "separates same variable name in different classes" do
      index.add_method_call(
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

      index.add_method_call(
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

      recipe_calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :instance_variables,
        scope_id: "Recipe",
        var_name: "@index",
        def_line: 3,
        def_column: 4
      )

      database_calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :instance_variables,
        scope_id: "Database",
        var_name: "@index",
        def_line: 20,
        def_column: 4
      )

      expect(recipe_calls.size).to eq(1)
      expect(recipe_calls[0][:method]).to eq("increment")

      expect(database_calls.size).to eq(1)
      expect(database_calls[0][:method]).to eq("fetch")
    end
  end

  describe "#find_definitions" do
    before do
      index.add_method_call(
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

      index.add_method_call(
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
    end

    it "finds all definitions of a variable" do
      all_defs = index.find_definitions(var_name: "@user")
      expect(all_defs.size).to eq(2)
    end

    it "filters by scope_type" do
      ivar_defs = index.find_definitions(var_name: "@user", scope_type: :instance_variables)
      expect(ivar_defs.size).to eq(1)
      expect(ivar_defs[0][:scope_id]).to eq("Recipe")
    end

    it "filters by file_path" do
      file1_defs = index.find_definitions(var_name: "@user", file_path: "/test/file1.rb")
      expect(file1_defs.size).to eq(1)
      expect(file1_defs[0][:file_path]).to eq("/test/file1.rb")
    end
  end

  describe "#find_variable_type_at_location" do
    it "finds type at location after definition" do
      index.add_variable_type(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Recipe#cook",
        var_name: "user",
        def_line: 5,
        def_column: 2,
        type: "User"
      )

      type = index.find_variable_type_at_location(
        var_name: "user",
        scope_type: :local_variables,
        max_line: 10,
        scope_id: "Recipe#cook"
      )

      expect(type).to eq("User")
    end

    it "returns nil before definition line" do
      index.add_variable_type(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Recipe#cook",
        var_name: "user",
        def_line: 5,
        def_column: 2,
        type: "User"
      )

      type = index.find_variable_type_at_location(
        var_name: "user",
        scope_type: :local_variables,
        max_line: 3,
        scope_id: "Recipe#cook"
      )

      expect(type).to be_nil
    end

    it "finds closest definition when multiple exist" do
      index.add_variable_type(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Recipe#cook",
        var_name: "item",
        def_line: 5,
        def_column: 2,
        type: "String"
      )

      index.add_variable_type(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Recipe#cook",
        var_name: "item",
        def_line: 10,
        def_column: 2,
        type: "Integer"
      )

      # At line 8, should find the first definition (String)
      type1 = index.find_variable_type_at_location(
        var_name: "item",
        scope_type: :local_variables,
        max_line: 8,
        scope_id: "Recipe#cook"
      )
      expect(type1).to eq("String")

      # At line 15, should find the second definition (Integer)
      type2 = index.find_variable_type_at_location(
        var_name: "item",
        scope_type: :local_variables,
        max_line: 15,
        scope_id: "Recipe#cook"
      )
      expect(type2).to eq("Integer")
    end

    it "searches broadly without scope_id" do
      index.add_variable_type(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Recipe#cook",
        var_name: "user",
        def_line: 5,
        def_column: 2,
        type: "User"
      )

      type = index.find_variable_type_at_location(
        var_name: "user",
        scope_type: :local_variables,
        max_line: 10
      )

      expect(type).to eq("User")
    end

    it "returns nil for nonexistent variable" do
      type = index.find_variable_type_at_location(
        var_name: "nonexistent",
        scope_type: :local_variables,
        max_line: 10,
        scope_id: "Recipe#cook"
      )

      expect(type).to be_nil
    end
  end
end
