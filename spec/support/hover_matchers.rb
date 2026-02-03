# frozen_string_literal: true

# Generic expect DSL for hover integration tests
# Use this module for testing hover functionality without doc generation dependencies
module HoverMatchers
  def expect_hover_type(line:, column:, expected:)
    response = hover_on_source(source, { line: line - 1, character: column })

    actual_type = extract_guessed_type(response&.contents&.value || "")

    expect(actual_type).to eq(expected),
                           "Expected type '#{expected}' but got '#{actual_type}'\n" \
                           "Full response: #{response&.contents&.value}"
  end

  def expect_hover_method_signature(line:, column:, expected_signature:)
    response = hover_on_source(source, { line: line - 1, character: column })

    expect(response).not_to be_nil

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

  private def extract_guessed_type(content)
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
end

RSpec.configure do |config|
  config.include HoverMatchers
end
