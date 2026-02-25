# TypeGuessr Benchmark Report

Generated: 2026-02-25 18:15:17

## Configuration

- **Target:** all
- **Files:** 3723
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3723 |
| Total nodes | 2147972 |
| Iterations | 3 |
| Avg time | 16.625 sec |
| Min/Max time | 15.170 / 19.050 sec |
| Throughput (nodes) | 129201 nodes/sec |
| Throughput (files) | 223.9 files/sec |
| Avg memory delta | +518322 KB |
| Avg time per file | 4.47 ms |
| Avg nodes per file | 576 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.273 ms |
| Max | 0.273 ms |
| Avg | 0.273 ms |
| Median (p50) | 0.273 ms |
| p95 | 0.273 ms |
| p99 | 0.273 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 3.717 sec |
| Throughput | 538 inferences/sec |
| Min | 0.001 ms |
| Max | 232.595 ms |
| Avg | 1.859 ms |
| Median (p50) | 0.050 ms |
| p95 | 6.092 ms |
| p99 | 33.630 ms |


## Performance Summary

- **Indexing**: 129201 nodes/sec (223.9 files/sec)
- **Inference**: 538 inferences/sec (1.859 ms/inference)

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
