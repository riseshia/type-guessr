# frozen_string_literal: true

require "fileutils"
require_relative "hover_matchers"

# Collects documented test examples and generates markdown documentation
module DocCollector
  class << self
    def entries
      @entries ||= []
    end

    def record(source:, line:, column:, expected:, group_hierarchy:, description:, spec_file:)
      entries << {
        type: :type_inference,
        source: source,
        line: line,
        column: column,
        expected: expected,
        group_hierarchy: group_hierarchy,
        description: description,
        spec_file: spec_file
      }
    end

    def record_method_signature(source:, line:, column:, expected_signature:, group_hierarchy:, description:, spec_file:)
      entries << {
        type: :method_signature,
        source: source,
        line: line,
        column: column,
        expected: expected_signature,
        group_hierarchy: group_hierarchy,
        description: description,
        spec_file: spec_file
      }
    end

    def generate!
      return if entries.empty?

      FileUtils.mkdir_p("docs")

      # Group entries by spec file
      entries_by_file = entries.group_by { |e| e[:spec_file] }

      total_examples = 0
      generated_files = []

      entries_by_file.each do |spec_file, file_entries|
        # Skip hover_spec.rb
        next if spec_file.include?("hover_spec.rb")

        doc_name = File.basename(spec_file, "_spec.rb")
        output_file = "docs/#{doc_name}.md"

        markdown = build_markdown_for_file(file_entries, doc_name)
        File.write(output_file, markdown)

        total_examples += file_entries.size
        generated_files << output_file
      end

      generated_files.each do |file|
        warn "Generated #{file}"
      end
      warn "Total: #{total_examples} examples in #{generated_files.size} files"
    end

    def reset!
      @entries = []
    end

    private def build_markdown_for_file(file_entries, doc_name)
      title = doc_name.split("_").map(&:capitalize).join(" ")
      output = "# #{title} Type Inference\n\n"
      output += "This document is auto-generated from tests tagged with `:doc`.\n\n"
      output += "> `[x]` marks the cursor position where hover was triggered.\n\n"

      # Group entries by hierarchy
      grouped = group_by_hierarchy(file_entries)

      grouped.each do |top_level, contexts|
        output += "## #{top_level}\n\n"

        contexts.each do |context_name, examples|
          output += "### #{context_name}\n\n"

          examples.each do |example|
            output += format_example(example)
          end
        end
      end

      output
    end

    private def group_by_hierarchy(file_entries)
      result = {}

      file_entries.each do |entry|
        hierarchy = entry[:group_hierarchy]
        top_level = hierarchy[0]
        context = hierarchy[1] || "General"

        result[top_level] ||= {}
        result[top_level][context] ||= []
        result[top_level][context] << entry
      end

      result
    end

    private def format_example(example)
      output = "```ruby\n"
      output += if example[:type] == :method_signature
                  add_signature_marker(example[:source], example[:line], example[:column], example[:expected])
                else
                  add_hover_marker(example[:source], example[:line], example[:column], example[:expected])
                end
      output += "```\n\n"
      output
    end

    private def add_hover_marker(source, line, column, expected_type)
      lines = source.lines
      return source if line > lines.size

      target_line = lines[line - 1]
      return source unless target_line

      content = target_line.rstrip

      # Insert brackets around the character at column position
      if column < content.length
        before = content[0...column]
        char = content[column] || ""
        after = content[(column + 1)..] || ""
        marked = "#{before}[#{char}]#{after}  # Guessed Type: #{expected_type}\n"
      else
        marked = "#{content}  # Guessed Type: #{expected_type}\n"
      end

      lines[line - 1] = marked
      lines.join
    end

    private def add_signature_marker(source, line, column, expected_signature)
      lines = source.lines
      return source if line > lines.size

      target_line = lines[line - 1]
      return source unless target_line

      content = target_line.rstrip

      # Insert brackets around the character at column position
      if column < content.length
        before = content[0...column]
        char = content[column] || ""
        after = content[(column + 1)..] || ""
        marked = "#{before}[#{char}]#{after}  # Signature: #{expected_signature}\n"
      else
        marked = "#{content}  # Signature: #{expected_signature}\n"
      end

      lines[line - 1] = marked
      lines.join
    end
  end
end

# Documentation-aware extension of HoverMatchers
# Records test examples for documentation generation when :doc tag is present
module TypeGuessrDocHelper
  include HoverMatchers

  def expect_hover_type(line:, column:, expected:)
    record_for_doc(:type_inference, line: line, column: column, expected: expected)
    super
  end

  def expect_hover_method_signature(line:, column:, expected_signature:)
    record_for_doc(:method_signature, line: line, column: column, expected_signature: expected_signature)
    super
  end

  private def record_for_doc(type, **kwargs)
    return unless RSpec.current_example.metadata[:doc]

    group_hierarchy = extract_group_hierarchy

    case type
    when :type_inference
      DocCollector.record(
        source: source,
        line: kwargs[:line],
        column: kwargs[:column],
        expected: kwargs[:expected],
        group_hierarchy: group_hierarchy,
        description: RSpec.current_example.description,
        spec_file: RSpec.current_example.metadata[:file_path]
      )
    when :method_signature
      DocCollector.record_method_signature(
        source: source,
        line: kwargs[:line],
        column: kwargs[:column],
        expected_signature: kwargs[:expected_signature],
        group_hierarchy: group_hierarchy,
        description: RSpec.current_example.description,
        spec_file: RSpec.current_example.metadata[:file_path]
      )
    end
  end

  private def extract_group_hierarchy
    hierarchy = []

    # Start from the current example's metadata
    metadata = RSpec.current_example.metadata
    found_doc_tag = false

    # Traverse up the example group hierarchy
    current = metadata[:example_group]
    while current
      # Check if this group has the :doc tag
      found_doc_tag = true if current[:doc]

      # Only collect descriptions after we find the :doc tag
      hierarchy.unshift(current[:description]) if found_doc_tag && current[:description] && !current[:description].empty?

      current = current[:parent_example_group]
    end

    # Remove the outermost group (e.g., "Hover Integration") if hierarchy has more than 2 levels
    # We want: [doc_group_name, context_name]
    hierarchy.shift if hierarchy.size > 2

    hierarchy
  end
end

RSpec.configure do |config|
  config.include TypeGuessrDocHelper

  config.after(:suite) do
    DocCollector.generate! if ENV["GENERATE_DOCS"]
  end
end
