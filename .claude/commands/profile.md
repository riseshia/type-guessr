---
description: Profile TypeGuessr performance (indexing & type inference)
allowed-tools: Bash(bin/profile:*), Bash(stackprof:*), Bash(mkdir:*), Read, Write
---

## Context

TypeGuessr performance profiling using stackprof.

## Your task

Run comprehensive performance profiling on TypeGuessr and generate a report.

### Step 1: CPU Profiling (Indexing + Inference)

Run CPU profiling with high resolution sampling:

```bash
bin/profile --target=all --mode=cpu --interval=100 --samples=200 --report
```

### Step 2: Memory Profiling (Object Allocations)

Run object allocation profiling:

```bash
bin/profile --target=indexing --mode=object --interval=1 --output=tmp/stackprof-memory.dump
```

Note: Object mode may take longer and use more memory.

### Step 3: Generate Flamegraphs

Generate interactive flamegraph visualizations:

```bash
stackprof --d3-flamegraph tmp/stackprof-all.dump > tmp/flamegraph-cpu.html
```

### Step 4: Analyze Results

After profiling completes:

1. Review the console output for top bottlenecks
2. Check `tmp/profile-report.md` for the summary
3. Open `tmp/flamegraph-cpu.html` in a browser for visual analysis

### Step 5: Report Key Findings

Summarize the profiling results:

1. **Top CPU bottlenecks** (methods taking >5% CPU time)
2. **Top memory allocators** (if object mode was run)
3. **GC overhead** percentage
4. **Specific recommendations** for optimization

Focus on actionable insights, especially:
- Methods in `TypeGuessr::Core::*` namespace
- `Prism::*` calls that could be optimized
- Object allocation hotspots

## Available Options

```
--target=indexing|inference|all  What to profile (default: all)
--mode=cpu|wall|object           Profiling mode (default: cpu)
--limit=N                        Max files to process
--samples=N                      Inference samples (default: 100)
--interval=N                     Sampling interval μs (default: 1000)
--path=PATH                      Project directory to profile (default: current)
--report                         Generate markdown report
```

## Profiling a Different Project

To profile TypeGuessr's performance on a large external project:

```bash
# Profile a Rails app
bin/profile --path=/path/to/rails-app --report

# CPU profile with high resolution
bin/profile --path=/path/to/large-project --target=indexing --mode=cpu --interval=100

# Memory analysis on external project
bin/profile --path=/path/to/project --mode=object --interval=1
```
