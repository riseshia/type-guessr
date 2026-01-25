# TypeGuessr Benchmark Report

Generated: 2026-01-25 10:16:39

## Configuration

- **Target:** all
- **Files:** 3330
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3330 |
| Total nodes | 546366 |
| Iterations | 3 |
| Avg time | 11.308 sec |
| Min/Max time | 10.864 / 12.169 sec |
| Throughput (nodes) | 48319 nodes/sec |
| Throughput (files) | 294.5 files/sec |
| Avg memory delta | +213340 KB |
| Avg time per file | 3.40 ms |
| Avg nodes per file | 164 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 726 |
| Min | 0.002 ms |
| Max | 107.190 ms |
| Avg | 0.169 ms |
| Median (p50) | 0.006 ms |
| p95 | 0.010 ms |
| p99 | 0.069 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 0.142 sec |
| Throughput | 14115 inferences/sec |
| Min | 0.001 ms |
| Max | 5.361 ms |
| Avg | 0.015 ms |
| Median (p50) | 0.006 ms |
| p95 | 0.015 ms |
| p99 | 0.052 ms |


## Performance Summary

- **Indexing**: 48319 nodes/sec (294.5 files/sec)
- **Inference**: 14115 inferences/sec (0.071 ms/inference)

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
