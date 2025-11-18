# frozen_string_literal: true

require "test_helper"
require "tempfile"

class TestTypeGuessr < Minitest::Test
  def test_analyze_file_returns_analysis_result
    # Create a temporary Ruby file
    Tempfile.create(["test", ".rb"]) do |file|
      file.write(<<~RUBY)
        def greet(name)
          puts "Hello, \#{name}"
        end
      RUBY
      file.flush

      result = TypeGuessr.analyze_file(file.path)

      assert_instance_of TypeGuessr::FileAnalysisResult, result
      assert_equal file.path, result.file_path
      assert_instance_of TypeGuessr::Core::VariableIndex, result.variable_index
    end
  end

  def test_analyze_file_with_nonexistent_file_raises_error
    assert_raises(TypeGuessr::Error) do
      TypeGuessr.analyze_file("/nonexistent/file.rb")
    end
  end

  def test_create_project_returns_project_instance
    Dir.mktmpdir do |dir|
      project = TypeGuessr.create_project(dir)

      assert_instance_of TypeGuessr::Project, project
      assert_equal dir, project.root_path
    end
  end

  def test_create_project_with_nonexistent_directory_raises_error
    assert_raises(TypeGuessr::Error) do
      TypeGuessr.create_project("/nonexistent/directory")
    end
  end
end
