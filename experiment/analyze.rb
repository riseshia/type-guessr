#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze experiment results from accumulated summary.csv.
#
# Usage:
#   ruby analyze.rb                                    # analyze accumulated results
#   ruby analyze.rb experiment/results/runs/20260317   # analyze a single run

require "csv"

CONDITIONS = %w[BASE LSP LSP_GUIDED TG_NATURAL TG_GUIDED].freeze

INT_FIELDS = %w[wall_ms duration_api_ms num_turns input_tokens output_tokens cache_read
                cache_creation result_length total_tool_calls standard_calls lsp_calls mcp_calls].freeze
FLOAT_FIELDS = %w[total_cost_usd lsp_ratio mcp_ratio].freeze

def load_results(csv_path)
  unless File.exist?(csv_path)
    warn "ERROR: #{csv_path} not found"
    exit 1
  end

  CSV.read(csv_path, headers: true).map do |row|
    h = row.to_h
    INT_FIELDS.each { |k| h[k] = h[k].to_i if h[k] }
    FLOAT_FIELDS.each { |k| h[k] = h[k].to_f if h[k] }
    h
  end
end

def avg(values)
  return 0.0 if values.empty?
  values.sum.to_f / values.size
end

def stddev(values)
  return 0.0 if values.size < 2
  mean = avg(values)
  Math.sqrt(values.map { |v| (v - mean)**2 }.sum / (values.size - 1))
end

def median(values)
  sorted = values.sort
  n = sorted.size
  return 0.0 if n == 0
  n.odd? ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
end

# Welch's t-test
def welch_t_test(a, b)
  n_a = a.size.to_f
  n_b = b.size.to_f
  return [0.0, 0.0, 1.0] if n_a < 2 || n_b < 2

  mean_a = avg(a)
  mean_b = avg(b)
  var_a = a.map { |v| (v - mean_a)**2 }.sum / (n_a - 1)
  var_b = b.map { |v| (v - mean_b)**2 }.sum / (n_b - 1)

  se = Math.sqrt(var_a / n_a + var_b / n_b)
  return [0.0, 0.0, 1.0] if se == 0

  t = (mean_a - mean_b) / se
  num = (var_a / n_a + var_b / n_b)**2
  den = (var_a / n_a)**2 / (n_a - 1) + (var_b / n_b)**2 / (n_b - 1)
  df = den > 0 ? num / den : 1.0

  p_value = t_distribution_p(t.abs, df)
  [t, df, p_value]
end

def t_distribution_p(t_abs, df)
  return 1.0 if t_abs == 0
  if df > 30
    return 2.0 * (1.0 - normal_cdf(t_abs))
  end
  x = df / (df + t_abs**2)
  p = regularized_beta(x, df / 2.0, 0.5)
  [p, 1.0].min
end

def normal_cdf(x)
  return 0.5 if x == 0
  return 1.0 - normal_cdf(-x) if x < 0
  t = 1.0 / (1.0 + 0.2316419 * x)
  pdf = Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math::PI)
  1.0 - pdf * t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
end

def regularized_beta(x, a, b)
  return 0.0 if x <= 0
  return 1.0 if x >= 1

  lbeta = Math.lgamma(a)[0] + Math.lgamma(b)[0] - Math.lgamma(a + b)[0]
  prefix = Math.exp(a * Math.log(x) + b * Math.log(1 - x) - lbeta) / a

  am = 1.0; bm = 1.0; az = 1.0
  bz = 1.0 - (a + b) * x / (a + 1)

  100.times do |m|
    em = m + 1
    d = em * (b - em) * x / ((a + 2 * em - 1) * (a + 2 * em))
    ap = az + d * am; bp = bz + d * bm
    d = -(a + em) * (a + b + em) * x / ((a + 2 * em) * (a + 2 * em + 1))
    am = ap + d * az; bm = bp + d * bz
    az = ap + d * ap; bz = bp + d * bp

    if bz.abs > 0
      old = az / bz
      az /= bz; am /= bz; bm /= bz; bz = 1.0
      break if (az - old).abs < 1e-10 * az.abs
    end
  end

  (prefix * az).clamp(0.0, 1.0)
end

def significance(p)
  return "***" if p < 0.001
  return "**" if p < 0.01
  return "*" if p < 0.05
  ""
end

def cohens_d(a, b)
  n_a = a.size.to_f
  n_b = b.size.to_f
  return 0.0 if n_a < 2 || n_b < 2

  mean_a = avg(a)
  mean_b = avg(b)
  var_a = a.map { |v| (v - mean_a)**2 }.sum / (n_a - 1)
  var_b = b.map { |v| (v - mean_b)**2 }.sum / (n_b - 1)

  pooled_sd = Math.sqrt(((n_a - 1) * var_a + (n_b - 1) * var_b) / (n_a + n_b - 2))
  return 0.0 if pooled_sd == 0

  (mean_a - mean_b) / pooled_sd
end

def analyze(rows)
  tasks = rows.map { |r| r["task"] }.uniq.sort
  total_runs = rows.select { |r| r["success"].to_s == "true" }.size

  puts "=" * 70
  puts "  Experiment Analysis (#{total_runs} successful runs)"
  puts "=" * 70

  # --- Per-task summary ---
  tasks.each do |task|
    puts "\n  #{task}"
    puts "  " + "-" * 66
    puts format("  %-12s %8s %8s %8s %8s %8s %3s",
      "Condition", "Time(s)", "Cost($)", "Tools", "MCP%", "Tokens", "N")

    CONDITIONS.each do |cond|
      task_rows = rows.select { |r| r["task"] == task && r["condition"] == cond && r["success"].to_s == "true" }
      next if task_rows.empty?

      times = task_rows.map { |r| r["wall_ms"] / 1000.0 }
      costs = task_rows.map { |r| r["total_cost_usd"] }
      tools = task_rows.map { |r| r["total_tool_calls"] }
      mcp = task_rows.map { |r| (r["mcp_ratio"] * 100).round }
      tokens = task_rows.map { |r| r["input_tokens"] + r["output_tokens"] }

      puts format("  %-12s %7.1f %8.4f %7.1f %7.0f%% %7.0f %3d",
        cond, avg(times), avg(costs), avg(tools), avg(mcp), avg(tokens), task_rows.size)
    end
  end

  # --- Cross-task summary ---
  puts "\n" + "=" * 70
  puts "  Cross-task Summary"
  puts "=" * 70
  puts format("  %-12s %8s %8s %8s %8s %8s %3s",
    "Condition", "Time(s)", "Cost($)", "Tools", "MCP%", "Tokens", "N")

  CONDITIONS.each do |cond|
    cond_rows = rows.select { |r| r["condition"] == cond && r["success"].to_s == "true" }
    next if cond_rows.empty?

    times = cond_rows.map { |r| r["wall_ms"] / 1000.0 }
    costs = cond_rows.map { |r| r["total_cost_usd"] }
    tools = cond_rows.map { |r| r["total_tool_calls"] }
    mcp = cond_rows.map { |r| (r["mcp_ratio"] * 100).round }
    tokens = cond_rows.map { |r| r["input_tokens"] + r["output_tokens"] }

    puts format("  %-12s %4.1f+/-%-4.1f $%5.3f+/-%5.3f %4.1f+/-%-4.1f %4.0f%%+/-%-3.0f%% %6.0f %3d",
      cond, avg(times), stddev(times), avg(costs), stddev(costs),
      avg(tools), stddev(tools), avg(mcp), stddev(mcp), avg(tokens), cond_rows.size)
  end

  # --- Statistical tests: BASE vs TG_GUIDED ---
  puts "\n" + "=" * 70
  puts "  Statistical Tests (BASE vs TG_GUIDED)"
  puts "=" * 70

  base_rows = rows.select { |r| r["condition"] == "BASE" && r["success"].to_s == "true" }
  tg_rows = rows.select { |r| r["condition"] == "TG_GUIDED" && r["success"].to_s == "true" }

  if base_rows.size >= 2 && tg_rows.size >= 2
    %w[wall_ms total_cost_usd total_tool_calls].each do |metric|
      a = base_rows.map { |r| r[metric].to_f }
      b = tg_rows.map { |r| r[metric].to_f }

      t, df, p = welch_t_test(a, b)
      d = cohens_d(a, b)
      sig = significance(p)
      delta = ((avg(b) - avg(a)) / avg(a) * 100).round(1)

      puts format("  %-20s  delta=%+.1f%%  t=%.2f  df=%.1f  p=%.4f %s  d=%.2f",
        metric, delta, t, df, p, sig, d)
    end
  else
    puts "  Not enough data for statistical tests (need n>=2 per condition)"
  end
end

if __FILE__ == $0
  path = ARGV[0] || File.join(__dir__, "results", "accumulated")

  csv_path = if File.directory?(path)
    File.join(path, "summary.csv")
  else
    path
  end

  rows = load_results(csv_path)
  analyze(rows)
end
