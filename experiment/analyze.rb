#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze experiment results from summary.csv.
#
# Usage: ruby analyze.rb <results_dir>
#        ruby analyze.rb experiment/results/20260311_220807

require "csv"

TASK_LABELS = {
  "t1_method_flow" => "T1: Method Flow Tracing (large-scale)",
  "t2_module_api" => "T2: Module API Listing (small-scale)",
}.freeze

CONDITIONS = %w[BASE_P0 LSP_P0 LSP_P1 TG_P0 TG_P1].freeze

INT_FIELDS = %w[duration_ms duration_api_ms num_turns input_tokens output_tokens cache_read
                cache_creation result_length total_tool_calls standard_calls lsp_calls mcp_calls].freeze
FLOAT_FIELDS = %w[total_cost_usd lsp_ratio mcp_ratio].freeze

def load_results(results_dir)
  csv_path = File.join(results_dir, "summary.csv")
  unless File.exist?(csv_path)
    warn "ERROR: #{csv_path} not found"
    exit 1
  end

  CSV.read(csv_path, headers: true).map do |row|
    h = row.to_h
    INT_FIELDS.each { |k| h[k] = h[k].to_i }
    FLOAT_FIELDS.each { |k| h[k] = h[k].to_f }
    h
  end
end

def avg(values)
  return 0.0 if values.empty?

  values.sum.to_f / values.size
end

def section(title)
  puts
  puts "=" * 70
  puts "  #{title}"
  puts "=" * 70
end

def shorten(name)
  name.to_s.gsub("mcp__type-guessr__", "tg:")
end

def analyze(rows)
  tasks = rows.map { |r| r["task"] }.uniq.sort
  grouped = rows.group_by { |r| [r["task"], r["condition"]] }

  # --- Per-task comparison ---
  tasks.each do |task|
    label = TASK_LABELS.fetch(task, task)
    section(label)

    header = format("%-10s %8s %8s %8s %8s %6s %6s %5s %5s %5s %6s %-30s",
      "Cond", "Wall(s)", "API(s)", "Over(s)", "Cost($)", "Turns", "Tools", "Std", "LSP", "MCP", "MCP%", "1st Tool")
    puts header
    puts "-" * header.size

    baseline_cost = nil
    CONDITIONS.each do |cond|
      rs = grouped[[task, cond]] || []
      next if rs.empty?

      dur     = avg(rs.map { |r| r["duration_ms"] / 1000.0 })
      dur_api = avg(rs.map { |r| r["duration_api_ms"] / 1000.0 })
      overhead = dur - dur_api
      cost  = avg(rs.map { |r| r["total_cost_usd"] })
      turns = avg(rs.map { |r| r["num_turns"] })
      tools = avg(rs.map { |r| r["total_tool_calls"] })
      std   = avg(rs.map { |r| r["standard_calls"] })
      lsp   = avg(rs.map { |r| r["lsp_calls"] })
      mcp   = avg(rs.map { |r| r["mcp_calls"] })
      mcp_r = avg(rs.map { |r| r["mcp_ratio"] })

      firsts = rs.map { |r| r["first_tool"] }
      first = firsts.tally.max_by(&:last)&.first || ""

      baseline_cost = cost if cond == "BASE_P0"

      delta = ""
      if baseline_cost && cond != "BASE_P0" && baseline_cost > 0
        pct = ((cost / baseline_cost) - 1) * 100
        delta = format(" (%+.0f%%)", pct)
      end

      puts format("%-10s %8.1f %8.1f %8.1f %7.4f%-7s %6.1f %6.1f %5.1f %5.1f %5.1f %5.0f%% %-30s",
        cond, dur, dur_api, overhead, cost, delta, turns, tools, std, lsp, mcp, mcp_r * 100, shorten(first))
    end
  end

  # --- Cross-condition summary ---
  section("Cross-condition Summary (averaged across tasks)")

  CONDITIONS.each do |cond|
    rs = rows.select { |r| r["condition"] == cond }
    next if rs.empty?

    cost     = avg(rs.map { |r| r["total_cost_usd"] })
    dur      = avg(rs.map { |r| r["duration_ms"] / 1000.0 })
    dur_api  = avg(rs.map { |r| r["duration_api_ms"] / 1000.0 })
    overhead = dur - dur_api
    tools = avg(rs.map { |r| r["total_tool_calls"] })
    mcp_r = avg(rs.map { |r| r["mcp_ratio"] })
    lsp_r = avg(rs.map { |r| r["lsp_ratio"] })

    puts format("  %-10s  cost=$%.4f  wall=%.1fs  api=%.1fs  overhead=%.1fs  tools=%.1f  lsp%%=%.0f%%  mcp%%=%.0f%%",
      cond, cost, dur, dur_api, overhead, tools, lsp_r * 100, mcp_r * 100)
  end

  # --- Key comparisons ---
  section("Key Comparisons")

  comparisons = [
    %w[BASE_P0 TG_P0], "Baseline vs MCP (natural)",
    %w[BASE_P0 TG_P1], "Baseline vs MCP (guided)",
    %w[BASE_P0 LSP_P0], "Baseline vs LSP (natural)",
    %w[LSP_P0 TG_P0], "LSP vs MCP (both natural)",
    %w[LSP_P1 TG_P1], "LSP vs MCP (both guided)",
    %w[TG_P0 TG_P1], "MCP natural vs guided",
    %w[LSP_P0 LSP_P1], "LSP natural vs guided",
  ].each_slice(2) do |(cond_a, cond_b), label|
    rs_a = rows.select { |r| r["condition"] == cond_a }
    rs_b = rows.select { |r| r["condition"] == cond_b }
    next if rs_a.empty? || rs_b.empty?

    cost_a = avg(rs_a.map { |r| r["total_cost_usd"] })
    cost_b = avg(rs_b.map { |r| r["total_cost_usd"] })
    dur_a  = avg(rs_a.map { |r| r["duration_ms"] / 1000.0 })
    dur_b  = avg(rs_b.map { |r| r["duration_ms"] / 1000.0 })
    api_a  = avg(rs_a.map { |r| r["duration_api_ms"] / 1000.0 })
    api_b  = avg(rs_b.map { |r| r["duration_api_ms"] / 1000.0 })

    cost_d = cost_a > 0 ? ((cost_b / cost_a) - 1) * 100 : 0
    dur_d  = dur_a > 0 ? ((dur_b / dur_a) - 1) * 100 : 0
    api_d  = api_a > 0 ? ((api_b / api_a) - 1) * 100 : 0

    puts format("  %s:", label)
    puts format("    Cost:     $%.4f → $%.4f (%+.0f%%)", cost_a, cost_b, cost_d)
    puts format("    Wall:     %.1fs → %.1fs (%+.0f%%)", dur_a, dur_b, dur_d)
    puts format("    API time: %.1fs → %.1fs (%+.0f%%)", api_a, api_b, api_d)
  end

  # --- Tool adoption (P0) ---
  section("Tool Adoption (P0 conditions only)")

  %w[LSP_P0 TG_P0].each do |cond|
    rs = rows.select { |r| r["condition"] == cond }
    next if rs.empty?

    tool_label = cond.start_with?("LSP") ? "LSP" : "MCP"
    ratio_key = cond.start_with?("LSP") ? "lsp_ratio" : "mcp_ratio"
    adoption = avg(rs.map { |r| r[ratio_key] })

    puts
    puts format("  %s (%s available, no guidance):", cond, tool_label)
    puts format("    Overall %s adoption: %.0f%%", tool_label, adoption * 100)

    tasks.each do |task|
      task_rs = rs.select { |r| r["task"] == task }
      next if task_rs.empty?

      ratio = avg(task_rs.map { |r| r[ratio_key] })
      seqs = task_rs.map { |r| r["tool_sequence"] }
      puts format("    %s: %s_ratio=%.0f%%  sequences=%s", task, tool_label, ratio * 100, seqs.inspect)
    end
  end

  # --- Tool sequence patterns ---
  section("Tool Sequence Patterns")

  tasks.each do |task|
    puts
    puts "  #{task}:"
    CONDITIONS.each do |cond|
      (grouped[[task, cond]] || []).each do |r|
        seq = shorten(r["tool_sequence"].to_s)
        puts format("    %s t%s: %s", cond, r["trial"], seq)
      end
    end
  end
end

if __FILE__ == $0
  if ARGV.size != 1
    warn "Usage: #{$0} <results_dir>"
    exit 1
  end

  rows = load_results(ARGV[0])
  analyze(rows)
end
