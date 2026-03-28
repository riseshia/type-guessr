#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract tool usage from a Claude Code session JSONL file.
#
# Usage: ruby extract_tools.rb <session.jsonl>

require "json"

STANDARD_TOOLS = %w[Bash Read Grep Glob Write Edit].freeze

def categorize(name)
  if name.start_with?("mcp__type") || name.include?("type-guessr") || name.include?("type_guessr")
    "type_guessr"
  elsif name == "LSP" || name.start_with?("lsp_")
    "lsp"
  elsif STANDARD_TOOLS.include?(name)
    "standard"
  else
    "other"
  end
end

def extract_tool_usage(jsonl_path)
  tool_calls = []
  tool_counts = Hash.new(0)
  categories = Hash.new(0)

  File.foreach(jsonl_path, encoding: "UTF-8") do |line|
    entry = JSON.parse(line)
    next unless entry["type"] == "assistant"

    content = entry.dig("message", "content") || []
    content.each do |block|
      next unless block.is_a?(Hash) && block["type"] == "tool_use"

      name = block["name"] || "unknown"

      # Skip warmup sleep call
      if name == "Bash"
        input = block["input"] || {}
        cmd = input["command"].to_s
        next if cmd.match?(/\A(sleep\s+\d+|bash\s+experiment\/warmup\.sh)\z/)
      end

      tool_calls << name
      tool_counts[name] += 1
      categories[categorize(name)] += 1
    end
  rescue JSON::ParserError
    next
  end

  total = tool_calls.size
  {
    total_tool_calls: total,
    tool_counts: tool_counts.sort_by { |_, v| -v }.to_h,
    tool_sequence: tool_calls,
    categories: categories,
    lsp_ratio: total > 0 ? categories["lsp"].to_f / total : 0,
    mcp_ratio: total > 0 ? categories["type_guessr"].to_f / total : 0,
    standard_ratio: total > 0 ? categories["standard"].to_f / total : 0,
    first_tool: tool_calls.first,
  }
end

if __FILE__ == $0
  if ARGV.size != 1
    warn "Usage: #{$0} <session.jsonl>"
    exit 1
  end

  puts JSON.pretty_generate(extract_tool_usage(ARGV[0]))
end
