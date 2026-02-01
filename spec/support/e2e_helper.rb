# frozen_string_literal: true

require "fileutils"
require_relative "shared_lsp_server"

# Helper module for E2E tests.
# Provides convenient methods for working with the shared LSP server.
# Automatically included in specs tagged with :e2e via config.include.
module E2EHelper
  def server
    SharedLspServer.instance
  end

  # Create a temporary Ruby file with the given content.
  # Returns the absolute path to the file.
  def create_temp_file(content, filename: "e2e_test.rb")
    path = File.join(Dir.pwd, "tmp", filename)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # Clean up temporary files created during tests.
  def cleanup_temp_files
    tmp_dir = File.join(Dir.pwd, "tmp")
    FileUtils.rm_rf(tmp_dir)
  end

  # Query hover on a temporary file with the given source.
  # Line and column are 1-based.
  def hover_on_temp_source(source, line, column, filename: "e2e_test.rb")
    path = create_temp_file(source, filename: filename)
    server.query_hover(path, line, column)
  ensure
    cleanup_temp_files
  end
end

# Custom RSpec matchers for E2E tests
RSpec::Matchers.define :include_type do |expected_type|
  match do |hover_content|
    return false if hover_content.nil?

    hover_content.include?(expected_type)
  end

  failure_message do |hover_content|
    if hover_content.nil?
      "expected hover content to include type '#{expected_type}', but hover returned nil"
    else
      "expected hover content to include type '#{expected_type}'\n\nActual content:\n#{hover_content}"
    end
  end
end

RSpec::Matchers.define :include_method_signature do |expected_signature|
  match do |hover_content|
    return false if hover_content.nil?

    hover_content.include?("Guessed Signature") && hover_content.include?(expected_signature)
  end

  failure_message do |hover_content|
    if hover_content.nil?
      "expected hover to include method signature '#{expected_signature}', but hover returned nil"
    else
      "expected hover to include method signature '#{expected_signature}'\n\nActual content:\n#{hover_content}"
    end
  end
end
