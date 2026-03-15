# TypeGuessr Benchmark Report

Generated: 2026-03-15 21:54:25

## Configuration

- **Target:** all
- **Files:** 3796
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3796 |
| Total nodes | 2144376 |
| Iterations | 3 |
| Avg time | 15.296 sec |
| Min/Max time | 14.306 / 17.263 sec |
| Throughput (nodes) | 140189 nodes/sec |
| Throughput (files) | 248.2 files/sec |
| Avg memory delta | +543389 KB |
| Avg time per file | 4.03 ms |
| Avg nodes per file | 564 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.182 ms |
| Max | 0.182 ms |
| Avg | 0.182 ms |
| Median (p50) | 0.182 ms |
| p95 | 0.182 ms |
| p99 | 0.182 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 3.640 sec |
| Throughput | 549 inferences/sec |
| Min | 0.001 ms |
| Max | 135.117 ms |
| Avg | 1.821 ms |
| Median (p50) | 0.051 ms |
| p95 | 7.181 ms |
| p99 | 31.886 ms |


## Performance Summary

- **Indexing**: 140189 nodes/sec (248.2 files/sec)
- **Inference**: 549 inferences/sec (1.820 ms/inference)

---

## How to Use

```bash
# Full benchmark
bin/benchmark

# With report (saved to docs/benchmark-report.md)
bin/benchmark --report

# Indexing only
bin/benchmark --target=indexing

# Inference only
bin/benchmark --target=inference
```
