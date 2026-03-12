#!/usr/bin/env ruby
# frozen_string_literal: true

# Extract assistant answer text from a Claude Code session JSONL or result JSON.
#
# Usage:
#   ruby extract_answer.rb <result_json>          # extracts from session JSONL via session_id
#   ruby extract_answer.rb <session_jsonl>         # extracts directly from session JSONL
#   ruby extract_answer.rb <results_dir>           # batch: extracts all answers in a results dir
#
# Output: assistant text (all text blocks concatenated, excluding warmup final message)

require "json"

CLAUDE_PROJECTS_DIR = File.expand_path("~/.claude/projects")

def find_session_jsonl(session_id)
  Dir.glob(File.join(CLAUDE_PROJECTS_DIR, "**", "#{session_id}.jsonl")).first
end

def extract_from_jsonl(jsonl_path)
  texts = []

  File.readlines(jsonl_path, encoding: "UTF-8").each do |line|
    d = JSON.parse(line)
    next unless d["type"] == "assistant"

    msg = d["message"]
    next unless msg && msg["content"]

    msg["content"].each do |block|
      next unless block["type"] == "text"

      text = block["text"].strip
      # Skip short warmup acknowledgement messages
      next if text.size < 100 && text.match?(/warmup.*complete|script.*success/i)

      texts << text
    end
  end

  texts.join("\n\n---\n\n")
end

def extract_from_result_json(result_path)
  d = JSON.parse(File.read(result_path, encoding: "UTF-8"))
  session_id = d["session_id"]

  unless session_id && !session_id.empty?
    warn "No session_id in #{result_path}"
    return nil
  end

  jsonl_path = find_session_jsonl(session_id)
  unless jsonl_path
    warn "Session JSONL not found for #{session_id}"
    return nil
  end

  extract_from_jsonl(jsonl_path)
end

def batch_extract(results_dir)
  Dir.glob(File.join(results_dir, "*.json")).sort.each do |result_file|
    basename = File.basename(result_file, ".json")
    next if basename.end_with?("_tools")
    next if basename.end_with?("_warmup")

    answer = extract_from_result_json(result_file)
    next unless answer

    output_path = result_file.sub(/\.json$/, "_answer.txt")
    File.write(output_path, answer, encoding: "UTF-8")
    puts "#{basename}: #{answer.size} chars"
  end
end

if __FILE__ == $0
  if ARGV.size != 1
    warn "Usage: #{$0} <result_json|session_jsonl|results_dir>"
    exit 1
  end

  path = ARGV[0]

  if File.directory?(path)
    batch_extract(path)
  elsif path.end_with?(".jsonl")
    puts extract_from_jsonl(path)
  elsif path.end_with?(".json")
    answer = extract_from_result_json(path)
    puts answer if answer
  else
    warn "Unknown file type: #{path}"
    exit 1
  end
end
