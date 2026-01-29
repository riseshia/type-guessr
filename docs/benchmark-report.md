# TypeGuessr Benchmark Report

Generated: 2026-01-29 20:51:31

## Configuration

- **Target:** all
- **Files:** 3331
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3331 |
| Total nodes | 1969019 |
| Iterations | 3 |
| Avg time | 12.146 sec |
| Min/Max time | 11.245 / 13.458 sec |
| Throughput (nodes) | 162115 nodes/sec |
| Throughput (files) | 274.3 files/sec |
| Avg memory delta | +569137 KB |
| Avg time per file | 3.65 ms |
| Avg nodes per file | 591 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.049 ms |
| Max | 0.049 ms |
| Avg | 0.049 ms |
| Median (p50) | 0.049 ms |
| p95 | 0.049 ms |
| p99 | 0.049 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 1997 |
| Total time | 0.013 sec |
| Throughput | 151234 inferences/sec |
| Min | 0.001 ms |
| Max | 0.102 ms |
| Avg | 0.007 ms |
| Median (p50) | 0.004 ms |
| p95 | 0.020 ms |
| p99 | 0.043 ms |


## Performance Summary

- **Indexing**: 162115 nodes/sec (274.3 files/sec)
- **Inference**: 151234 inferences/sec (0.007 ms/inference)

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
