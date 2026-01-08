# frozen_string_literal: true

require "fileutils"

# Collects documented test examples and generates markdown documentation
module DocCollector
  class << self
    def entries
      @entries ||= []
    end

    def record(source:, line:, column:, expected:, group_hierarchy:, description:)
      entries << {
        type: :type_inference,
        source: source,
        line: line,
        column: column,
        expected: expected,
        group_hierarchy: group_hierarchy,
        description: description
      }
    end

    def record_method_signature(source:, line:, column:, expected_signature:, group_hierarchy:, description:)
      entries << {
        type: :method_signature,
        source: source,
        line: line,
        column: column,
        expected: expected_signature,
        group_hierarchy: group_hierarchy,
        description: description
      }
    end

    def generate!
      return if entries.empty?

      markdown = build_markdown
      FileUtils.mkdir_p("docs")
      File.write("docs/inference_rules.md", markdown)

      warn "Generated docs/inference_rules.md with #{entries.size} examples"
    end

    def reset!
      @entries = []
    end

    private

    def build_markdown
      output = "# Type Inference Rules\n\n"
      output += "This document is auto-generated from tests tagged with `:doc`.\n\n"

      # Group entries by hierarchy
      grouped = group_by_hierarchy(entries)

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

    def group_by_hierarchy(entries)
      result = {}

      entries.each do |entry|
        hierarchy = entry[:group_hierarchy]
        top_level = hierarchy[0]
        context = hierarchy[1] || "General"

        result[top_level] ||= {}
        result[top_level][context] ||= []
        result[top_level][context] << entry
      end

      result
    end

    def format_example(example)
      output = "```ruby\n"
      output += if example[:type] == :method_signature
                  add_signature_marker(example[:source], example[:line], example[:column], example[:expected])
                else
                  add_hover_marker(example[:source], example[:line], example[:column], example[:expected])
                end
      output += "```\n\n"
      output
    end

    def add_hover_marker(source, line, column, expected_type)
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

    def add_signature_marker(source, line, column, expected_signature)
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

# Helper module for documented tests
module TypeGuessrDocHelper
  def expect_hover_type(line:, column:, expected:)
    source = self.source

    # Record if this is a documented example
    if RSpec.current_example.metadata[:doc]
      group_hierarchy = extract_group_hierarchy
      DocCollector.record(
        source: source,
        line: line,
        column: column,
        expected: expected,
        group_hierarchy: group_hierarchy,
        description: RSpec.current_example.description
      )
    end

    # Perform actual hover test
    response = hover_on_source(source, { line: line - 1, character: column })

    # Extract actual type from response
    # Formats:
    #   Plain: **Guessed Type:** `Recipe`
    #   Linked: **Guessed Type:** [`Recipe`](file://...)
    actual_type = extract_guessed_type(response.contents.value)

    expect(actual_type).to eq(expected),
                           "Expected type '#{expected}' but got '#{actual_type}'\n" \
                           "Full response: #{response.contents.value}"
  end

  def extract_guessed_type(content)
    # Try linked format first: [`Type`](url)
    if (match = content.match(/Guessed Type:\*\*\s*\[`([^`]+)`\]/))
      return match[1]
    end

    # Try plain format: `Type`
    if (match = content.match(/Guessed Type:\*\*\s*`([^`]+)`/))
      return match[1]
    end

    # Try Guessed Signature format: `(params) -> ReturnType`
    # Extract return type from signature
    if (match = content.match(/Guessed Signature:\*\*\s*`\([^)]*\)\s*->\s*([^`]+)`/))
      return match[1]
    end

    ""
  end

  def expect_hover_method_signature(line:, column:, expected_signature:)
    source = self.source

    # Record if this is a documented example
    if RSpec.current_example.metadata[:doc]
      group_hierarchy = extract_group_hierarchy
      DocCollector.record_method_signature(
        source: source,
        line: line,
        column: column,
        expected_signature: expected_signature,
        group_hierarchy: group_hierarchy,
        description: RSpec.current_example.description
      )
    end

    # Perform actual hover test
    response = hover_on_source(source, { line: line - 1, character: column })

    # Validate response exists
    expect(response).not_to be_nil

    # Match expected signature
    escaped_signature = Regexp.escape(expected_signature)
    expect(response.contents.value).to match(/#{escaped_signature}/)
  end

  # Expect hover response exists with non-empty content
  # Use this when you just want to verify hover works, regardless of specific type
  def expect_hover_response(line:, column:)
    response = hover_on_source(source, { line: line - 1, character: column })
    expect(response).not_to be_nil, "Expected hover response at line #{line}, column #{column}"
    expect(response.contents.value).not_to be_nil
    expect(response.contents.value).not_to be_empty
    response
  end

  # Expect no crash - hover may return nil or a valid response
  # Use this for edge cases where inference might fail gracefully
  def expect_no_hover_crash(line:, column:)
    response = hover_on_source(source, { line: line - 1, character: column })
    expect(response).to be_nil.or(be_a(RubyLsp::Interface::Hover))
    response
  end

  # Expect hover type excludes ALL of the given types
  # Use this to verify certain types are NOT inferred
  def expect_hover_type_excludes(line:, column:, types:)
    response = hover_on_source(source, { line: line - 1, character: column })
    expect(response).not_to be_nil, "Expected hover response at line #{line}, column #{column}"

    types.each do |type|
      escaped_type = Regexp.escape(type)
      expect(response.contents.value).not_to match(/#{escaped_type}/),
                                             "Expected hover NOT to include type '#{type}', got: #{response.contents.value}"
    end
    response
  end

  private

  def extract_group_hierarchy
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
