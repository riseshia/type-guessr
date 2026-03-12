#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze experiment results from summary.csv.
#
# Usage: ruby analyze.rb <results_dir>
#        ruby analyze.rb experiment/results/20260311_220807

require "csv"

TASK_LABELS = {
  "t1_return_type_chain" => "T1: Cross-file Return Type Chain",
  "t2_bug_localization" => "T2: Bug Localization (||= / OrNode)",
  "t3_yield_node_plan" => "T3: Implementation Plan (YieldNode)",
  "t4_api_comparison" => "T4: API Surface Comparison",
}.freeze

CONDITIONS = %w[BASE_P0 LSP_P0 LSP_P1 TG_P0 TG_P1].freeze

INT_FIELDS = %w[wall_ms duration_api_ms num_turns input_tokens output_tokens cache_read
                cache_creation result_length total_tool_calls standard_calls lsp_calls mcp_calls].freeze
FLOAT_FIELDS = %w[total_cost_usd lsp_ratio mcp_ratio quality_score completeness accuracy specificity].freeze

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

def stddev(values)
  return 0.0 if values.size < 2

  mean = avg(values)
  Math.sqrt(values.map { |v| (v - mean)**2 }.sum / (values.size - 1))
end

# Welch's t-test for unequal variances
# Returns [t_statistic, degrees_of_freedom, p_value]
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

  # Welch-Satterthwaite degrees of freedom
  num = (var_a / n_a + var_b / n_b)**2
  den = (var_a / n_a)**2 / (n_a - 1) + (var_b / n_b)**2 / (n_b - 1)
  df = den > 0 ? num / den : 1.0

  # Approximate two-tailed p-value using Student's t CDF
  # Uses regularized incomplete beta function approximation
  p_value = t_distribution_p(t.abs, df)

  [t, df, p_value]
end

# Approximate two-tailed p-value for Student's t-distribution
# Uses the approximation: p ≈ 2 * (1 - Φ(|t| * √(df/(df-2+t²))))
# Good enough for df > 4. For small df, use a more conservative estimate.
def t_distribution_p(t_abs, df)
  return 1.0 if t_abs == 0

  # For large df, t ≈ normal
  if df > 30
    # Normal approximation
    z = t_abs
    return 2.0 * (1.0 - normal_cdf(z))
  end

  # Approximation via normal CDF with correction
  x = df / (df + t_abs**2)
  p = regularized_beta(x, df / 2.0, 0.5)
  [p, 1.0].min
end

# Approximate normal CDF using Abramowitz and Stegun formula 7.1.26
def normal_cdf(x)
  return 0.5 if x == 0
  return 1.0 - normal_cdf(-x) if x < 0

  b0 = 0.2316419
  b1 = 0.319381530
  b2 = -0.356563782
  b3 = 1.781477937
  b4 = -1.821255978
  b5 = 1.330274429

  t = 1.0 / (1.0 + b0 * x)
  pdf = Math.exp(-0.5 * x * x) / Math.sqrt(2 * Math::PI)
  1.0 - pdf * t * (b1 + t * (b2 + t * (b3 + t * (b4 + t * b5))))
end

# Regularized incomplete beta function (rough approximation)
# Good enough for t-test p-value estimation
def regularized_beta(x, a, b)
  return 0.0 if x <= 0
  return 1.0 if x >= 1

  # Use continued fraction approximation (Lentz's algorithm, simplified)
  # For our use case (a=df/2, b=0.5), this converges quickly
  max_iter = 100
  eps = 1e-10

  # Beta function via log-gamma
  lbeta = Math.lgamma(a)[0] + Math.lgamma(b)[0] - Math.lgamma(a + b)[0]
  prefix = Math.exp(a * Math.log(x) + b * Math.log(1 - x) - lbeta) / a

  # Continued fraction
  am = 1.0
  bm = 1.0
  az = 1.0
  bz = 1.0 - (a + b) * x / (a + 1)

  m = 1
  while m < max_iter
    em = m
    d = em * (b - em) * x / ((a + 2 * em - 1) * (a + 2 * em))
    ap = az + d * am
    bp = bz + d * bm
    d = -(a + em) * (a + b + em) * x / ((a + 2 * em) * (a + 2 * em + 1))
    am = ap + d * az
    bm = bp + d * bz
    az = ap + d * ap
    bz = bp + d * bp

    if bz.abs > 0
      old = az / bz
      az /= bz
      am /= bz
      bm /= bz
      bz = 1.0
      break if (az - old).abs < eps * az.abs
    end

    m += 1
  end

  result = prefix * az
  result.clamp(0.0, 1.0)
end

# Format significance level
def significance(p)
  if p < 0.001
    "***"
  elsif p < 0.01
    "**"
  elsif p < 0.05
    "*"
  else
    ""
  end
end

# Cohen's d effect size
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

      dur     = avg(rs.map { |r| r["wall_ms"] / 1000.0 })
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
    dur      = avg(rs.map { |r| r["wall_ms"] / 1000.0 })
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
    dur_a  = avg(rs_a.map { |r| r["wall_ms"] / 1000.0 })
    dur_b  = avg(rs_b.map { |r| r["wall_ms"] / 1000.0 })
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

  # --- Statistical comparisons ---
  section("Statistical Comparisons (Welch's t-test)")

  comparisons = [
    %w[BASE_P0 TG_P0], "Baseline vs MCP (natural)",
    %w[BASE_P0 TG_P1], "Baseline vs MCP (guided)",
    %w[BASE_P0 LSP_P0], "Baseline vs LSP (natural)",
    %w[LSP_P0 TG_P0], "LSP vs MCP (both natural)",
    %w[LSP_P1 TG_P1], "LSP vs MCP (both guided)",
    %w[TG_P0 TG_P1], "MCP natural vs guided",
    %w[LSP_P0 LSP_P1], "LSP natural vs guided",
  ]

  metrics = [
    ["total_cost_usd", "Cost ($)"],
    ["wall_ms", "Wall (ms)"],
    ["total_tool_calls", "Tools"],
  ]

  # Check for quality scores
  has_quality = rows.any? { |r| r["quality_score"] && r["quality_score"].to_f > 0 }
  metrics << ["quality_score", "Quality"] if has_quality

  comparisons.each_slice(2) do |(cond_a, cond_b), label|
    rs_a = rows.select { |r| r["condition"] == cond_a }
    rs_b = rows.select { |r| r["condition"] == cond_b }
    next if rs_a.empty? || rs_b.empty?

    puts
    puts format("  %s (n=%d vs n=%d):", label, rs_a.size, rs_b.size)

    metrics.each do |field, field_label|
      vals_a = rs_a.map { |r| r[field].to_f }
      vals_b = rs_b.map { |r| r[field].to_f }

      mean_a = avg(vals_a)
      mean_b = avg(vals_b)
      sd_a = stddev(vals_a)
      sd_b = stddev(vals_b)
      t, df, p = welch_t_test(vals_a, vals_b)
      d = cohens_d(vals_a, vals_b)
      sig = significance(p)

      diff_pct = mean_a > 0 ? ((mean_b / mean_a) - 1) * 100 : 0

      puts format("    %-10s  %.3f±%.3f vs %.3f±%.3f  Δ=%+.0f%%  t=%.2f  p=%.4f%s  d=%.2f",
        field_label, mean_a, sd_a, mean_b, sd_b, diff_pct, t, p, sig, d)
    end
  end

  # --- Per-condition descriptive stats ---
  section("Descriptive Statistics (mean ± stddev)")

  puts format("  %-10s %16s %16s %16s %16s",
    "Condition", "Cost ($)", "Wall (s)", "Tools", has_quality ? "Quality" : "")
  puts "  " + "-" * 78

  CONDITIONS.each do |cond|
    rs = rows.select { |r| r["condition"] == cond }
    next if rs.empty?

    costs = rs.map { |r| r["total_cost_usd"] }
    walls = rs.map { |r| r["wall_ms"] / 1000.0 }
    tools = rs.map { |r| r["total_tool_calls"].to_f }

    line = format("  %-10s %6.4f ± %.4f %6.1f ± %5.1f %5.1f ± %4.1f",
      cond, avg(costs), stddev(costs), avg(walls), stddev(walls), avg(tools), stddev(tools))

    if has_quality
      quals = rs.map { |r| r["quality_score"].to_f }
      line += format(" %5.1f ± %4.1f", avg(quals), stddev(quals))
    end

    puts line
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
