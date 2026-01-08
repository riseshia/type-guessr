---
description: Benchmark TypeGuessr performance (indexing & inference throughput)
allowed-tools: Bash(bin/benchmark:*), Read, Write
---

## Context

TypeGuessr performance benchmarking using benchmark-ips.

## Your task

Run benchmarks on TypeGuessr indexing and inference performance.

### Step 1: Run Full Benchmark

Run comprehensive benchmark with report generation:

```bash
bin/benchmark --report
```

### Step 2: Analyze Results

Review the benchmark output:

1. **Indexing metrics:**
   - Total time for all files
   - Nodes/sec throughput
   - Files/sec throughput
   - Memory usage delta

2. **Inference metrics:**
   - Inferences/sec throughput
   - Average time per inference
   - Node type breakdown

3. **IPS comparisons:**
   - Compare different operations (parse vs convert)
   - Compare different node types for inference

### Step 3: Report Summary

Summarize the results:

1. **Overall throughput** (nodes/sec, inferences/sec)
2. **Bottleneck identification** (which operation is slowest)
3. **Memory efficiency** (memory per node)
4. **Comparison to previous runs** (if available in docs/benchmark-report.md)

The report is saved to `docs/benchmark-report.md` for version control.

## Available Options

```
--target=indexing|inference|all  What to benchmark (default: all)
--warmup=N                       Warmup time in seconds (default: 2)
--time=N                         Benchmark time in seconds (default: 5)
--samples=N                      Inference samples (default: 2000)
--path=PATH                      Project directory to benchmark (default: current)
--report                         Generate markdown report
```

## Quick Commands

```bash
# Full benchmark
bin/benchmark

# With report
bin/benchmark --report

# Indexing only
bin/benchmark --target=indexing

# Inference only
bin/benchmark --target=inference

# Benchmark a different project (e.g., large Rails app)
bin/benchmark --path=/path/to/rails-app --report
```
