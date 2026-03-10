# TypeGuessr Benchmark Report

Generated: 2026-03-10 21:52:24

## Configuration

- **Target:** all
- **Files:** 3755
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3755 |
| Total nodes | 2151458 |
| Iterations | 3 |
| Avg time | 13.250 sec |
| Min/Max time | 12.718 / 14.226 sec |
| Throughput (nodes) | 162378 nodes/sec |
| Throughput (files) | 283.4 files/sec |
| Avg memory delta | +549812 KB |
| Avg time per file | 3.53 ms |
| Avg nodes per file | 572 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.214 ms |
| Max | 0.214 ms |
| Avg | 0.214 ms |
| Median (p50) | 0.214 ms |
| p95 | 0.214 ms |
| p99 | 0.214 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 4.228 sec |
| Throughput | 473 inferences/sec |
| Min | 0.001 ms |
| Max | 193.743 ms |
| Avg | 2.115 ms |
| Median (p50) | 0.048 ms |
| p95 | 8.365 ms |
| p99 | 39.508 ms |


## Performance Summary

- **Indexing**: 162378 nodes/sec (283.4 files/sec)
- **Inference**: 473 inferences/sec (2.114 ms/inference)

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
