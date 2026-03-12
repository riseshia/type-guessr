#!/usr/bin/env ruby
# frozen_string_literal: true

# LLM-as-Judge: Score experiment answers against ground truth.
#
# Usage:
#   ruby judge.rb <results_dir>                    # score all answers
#   ruby judge.rb <results_dir> --task t1_return_type_chain  # score one task only
#   ruby judge.rb <results_dir> --dry-run          # show prompts without calling LLM
#
# Prerequisites:
#   - Run extract_answer.rb first to generate _answer.txt files
#   - Ground truth files in experiment/ground_truth/t{N}_*.md
#
# Output:
#   - Per-answer score files: <result>_score.json
#   - Summary: quality.csv

require "json"
require "csv"
require "open3"

GROUND_TRUTH_DIR = File.join(__dir__, "ground_truth")
JUDGE_MODEL = ENV.fetch("JUDGE_MODEL", "sonnet")

RUBRIC = <<~RUBRIC
  You are an expert code analysis evaluator. Score the student answer against the reference answer.

  ## Scoring Dimensions (each 0-10):

  ### Completeness (0-10)
  How many of the key facts/elements from the reference are covered?
  - 0: No relevant content
  - 3: Mentions the topic but misses most key elements
  - 5: Covers about half the key elements
  - 7: Covers most key elements with minor gaps
  - 10: All key elements from reference are present

  ### Accuracy (0-10)
  Are the stated facts correct? (file paths, method names, line numbers, logic descriptions)
  - 0: Mostly incorrect
  - 3: Several significant errors
  - 5: Mix of correct and incorrect
  - 7: Mostly correct with minor errors
  - 10: All stated facts are correct

  ### Depth (0-10)
  How well does the answer explain the underlying logic and connections?
  - 0: No explanation
  - 3: Surface-level listing only
  - 5: Some explanation of how things connect
  - 7: Good explanation with clear reasoning
  - 10: Deep understanding with nuanced connections

  ## Instructions
  1. Compare the student answer against the reference answer
  2. Score each dimension independently
  3. Provide brief justification for each score
  4. Respond ONLY with valid JSON in this exact format:

  ```json
  {
    "completeness": { "score": N, "justification": "..." },
    "accuracy": { "score": N, "justification": "..." },
    "depth": { "score": N, "justification": "..." },
    "overall": N,
    "summary": "One sentence overall assessment"
  }
  ```

  Where "overall" is the average of the three scores rounded to 1 decimal place.
RUBRIC

# Filename format: {task_id}_{condition}_{trial}.json
# e.g., t1_return_type_chain_BASE_P0_t1.json
FILENAME_PATTERN = /\A(.+)_(BASE_P0|LSP_P[01]|TG_P[01])_(t\d+)\z/

def parse_filename(basename)
  match = basename.match(FILENAME_PATTERN)
  return nil unless match

  { task: match[1], condition: match[2], trial: match[3] }
end

def load_ground_truth(task_name)
  path = File.join(GROUND_TRUTH_DIR, "#{task_name}.md")
  unless File.exist?(path)
    warn "Ground truth not found: #{path}"
    return nil
  end
  File.read(path, encoding: "UTF-8")
end

def build_judge_prompt(ground_truth, student_answer)
  <<~PROMPT
    #{RUBRIC}

    ## Reference Answer (Ground Truth)

    #{ground_truth}

    ## Student Answer

    #{student_answer}
  PROMPT
end

def call_judge(prompt)
  cmd = [
    "claude", "--print",
    "--output-format", "text",
    "--model", JUDGE_MODEL,
    "--max-turns", "1",
    prompt,
  ]

  stdout, stderr, status = Open3.capture3(
    { "CLAUDE_CODE_ENTRYPOINT" => "cli" },
    *cmd
  )

  unless status.success?
    warn "Judge call failed: #{stderr}"
    return nil
  end

  # Extract JSON from response (may be wrapped in ```json ... ```)
  json_str = stdout.strip
  json_str = json_str.gsub(/\A```json\s*/, "").gsub(/\s*```\z/, "")

  JSON.parse(json_str)
rescue JSON::ParserError => e
  warn "Failed to parse judge response: #{e.message}"
  warn "Raw response: #{stdout&.first(500)}"
  nil
end

def score_answer(result_file, task_name, dry_run: false)
  answer_file = result_file.sub(/\.json$/, "_answer.txt")
  score_file = result_file.sub(/\.json$/, "_score.json")

  # Skip if already scored
  return JSON.parse(File.read(score_file, encoding: "UTF-8")) if File.exist?(score_file)

  unless File.exist?(answer_file)
    warn "No answer file: #{answer_file}"
    return nil
  end

  student_answer = File.read(answer_file, encoding: "UTF-8")
  return nil if student_answer.strip.empty?

  # Truncate very long answers to save judge tokens
  max_chars = 15_000
  if student_answer.size > max_chars
    student_answer = student_answer[0...max_chars] + "\n\n[TRUNCATED - original #{student_answer.size} chars]"
  end

  ground_truth = load_ground_truth(task_name)
  return nil unless ground_truth

  prompt = build_judge_prompt(ground_truth, student_answer)

  if dry_run
    puts "--- Would judge: #{File.basename(result_file)} (task: #{task_name}) ---"
    puts "Prompt length: #{prompt.size} chars"
    return nil
  end

  score = call_judge(prompt)
  return nil unless score

  # Save score
  File.write(score_file, JSON.pretty_generate(score), encoding: "UTF-8")
  score
end

def run(results_dir, task_filter: nil, dry_run: false, parallel: 3)
  result_files = Dir.glob(File.join(results_dir, "*.json")).sort
  result_files.reject! { |f| File.basename(f) =~ /_(tools|warmup|answer|score)\.json$/ }

  scores = []
  queue = []

  result_files.each do |result_file|
    basename = File.basename(result_file, ".json")
    parsed = parse_filename(basename)
    next unless parsed
    next if task_filter && parsed[:task] != task_filter

    queue << { file: result_file, basename: basename, **parsed }
  end

  puts "Judging #{queue.size} answers (model: #{JUDGE_MODEL}, parallel: #{parallel})..."

  # Process with simple parallelism using threads
  mutex = Mutex.new
  completed = 0

  threads = queue.each_slice((queue.size.to_f / parallel).ceil).map do |batch|
    Thread.new do
      batch.each do |entry|
        score = score_answer(entry[:file], entry[:task], dry_run: dry_run)

        mutex.synchronize do
          completed += 1
          if score
            scores << { **entry, **score }
            overall = score["overall"] || "?"
            puts "[#{completed}/#{queue.size}] #{entry[:basename]}: overall=#{overall}"
          else
            puts "[#{completed}/#{queue.size}] #{entry[:basename]}: SKIPPED"
          end
        end
      end
    end
  end

  threads.each(&:join)

  return if dry_run || scores.empty?

  # Write quality.csv
  csv_path = File.join(results_dir, "quality.csv")
  CSV.open(csv_path, "w", encoding: "UTF-8") do |csv|
    csv << %w[file task condition trial completeness accuracy depth overall summary]

    scores.sort_by { |s| s[:basename] }.each do |s|
      csv << [
        s[:basename],
        s[:task],
        s[:condition],
        s[:trial].sub(/\At/, ""),
        s.dig("completeness", "score"),
        s.dig("accuracy", "score"),
        s.dig("depth", "score"),
        s["overall"],
        s["summary"],
      ]
    end
  end

  puts "\nQuality scores written to: #{csv_path}"

  # Print summary
  print_summary(scores)
end

def print_summary(scores)
  puts "\n#{"=" * 60}"
  puts "  Quality Summary"
  puts "=" * 60

  conditions = %w[BASE_P0 LSP_P0 LSP_P1 TG_P0 TG_P1]
  tasks = scores.map { |s| s[:task] }.uniq.sort

  avg = ->(arr) { arr.empty? ? 0.0 : arr.sum.to_f / arr.size }
  stddev = ->(arr) {
    return 0.0 if arr.size < 2

    mean = avg.call(arr)
    Math.sqrt(arr.map { |x| (x - mean)**2 }.sum / (arr.size - 1))
  }

  # Per-task breakdown
  tasks.each do |task|
    puts "\n  #{task}:"
    puts format("    %-10s %8s %8s %8s %8s %3s", "Cond", "Compl", "Acc", "Depth", "Overall", "N")
    puts "    " + "-" * 49

    conditions.each do |cond|
      cond_scores = scores.select { |s| s[:task] == task && s[:condition] == cond }
      next if cond_scores.empty?

      comp = cond_scores.map { |s| s.dig("completeness", "score") || 0 }
      acc = cond_scores.map { |s| s.dig("accuracy", "score") || 0 }
      depth = cond_scores.map { |s| s.dig("depth", "score") || 0 }
      overall = cond_scores.map { |s| s["overall"] || 0 }

      puts format("    %-10s %7.1f %8.1f %8.1f %8.1f %3d",
        cond, avg[comp], avg[acc], avg[depth], avg[overall], cond_scores.size)
    end
  end

  # Cross-condition summary
  puts "\n  Cross-condition average:"
  puts format("    %-10s %11s %11s %11s %11s %3s",
    "Cond", "Compl", "Acc", "Depth", "Overall", "N")
  puts "    " + "-" * 55

  conditions.each do |cond|
    cond_scores = scores.select { |s| s[:condition] == cond }
    next if cond_scores.empty?

    comp = cond_scores.map { |s| s.dig("completeness", "score") || 0 }
    acc = cond_scores.map { |s| s.dig("accuracy", "score") || 0 }
    depth = cond_scores.map { |s| s.dig("depth", "score") || 0 }
    overall = cond_scores.map { |s| s["overall"] || 0 }

    puts format("    %-10s %4.1f ± %4.1f %4.1f ± %4.1f %4.1f ± %4.1f %4.1f ± %4.1f %3d",
      cond,
      avg[comp], stddev[comp],
      avg[acc], stddev[acc],
      avg[depth], stddev[depth],
      avg[overall], stddev[overall],
      cond_scores.size)
  end
end

if __FILE__ == $0
  if ARGV.empty?
    warn "Usage: #{$0} <results_dir> [--task TASK] [--dry-run] [--parallel N] [--model MODEL]"
    exit 1
  end

  results_dir = ARGV[0]
  task_filter = nil
  dry_run = false
  parallel = 3

  i = 1
  while i < ARGV.size
    case ARGV[i]
    when "--task"
      task_filter = ARGV[i + 1]
      i += 2
    when "--dry-run"
      dry_run = true
      i += 1
    when "--parallel"
      parallel = ARGV[i + 1].to_i
      i += 2
    when "--model"
      ENV["JUDGE_MODEL"] = ARGV[i + 1]
      i += 2
    else
      i += 1
    end
  end

  unless File.directory?(results_dir)
    warn "ERROR: #{results_dir} is not a directory"
    exit 1
  end

  run(results_dir, task_filter: task_filter, dry_run: dry_run, parallel: parallel)
end
