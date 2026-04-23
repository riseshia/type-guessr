# TypeGuessr Benchmark Report

Generated: 2026-04-23 14:08:53

## Configuration

- **Target:** all
- **Files:** 3804
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3804 |
| Total nodes | 2089002 |
| Iterations | 3 |
| Avg time | 8.855 sec |
| Min/Max time | 8.057 / 10.141 sec |
| Throughput (nodes) | 235925 nodes/sec |
| Throughput (files) | 429.6 files/sec |
| Avg memory delta | +551909 KB |
| Avg time per file | 2.33 ms |
| Avg nodes per file | 549 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.111 ms |
| Max | 0.111 ms |
| Avg | 0.111 ms |
| Median (p50) | 0.111 ms |
| p95 | 0.111 ms |
| p99 | 0.111 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 2.902 sec |
| Throughput | 689 inferences/sec |
| Min | 0.000 ms |
| Max | 226.432 ms |
| Avg | 1.452 ms |
| Median (p50) | 0.023 ms |
| p95 | 4.404 ms |
| p99 | 24.293 ms |


## Performance Summary

- **Indexing**: 235925 nodes/sec (429.6 files/sec)
- **Inference**: 689 inferences/sec (1.451 ms/inference)

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
