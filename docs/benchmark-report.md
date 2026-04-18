# TypeGuessr Benchmark Report

Generated: 2026-04-19 08:17:00

## Configuration

- **Target:** all
- **Files:** 3559
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3559 |
| Total nodes | 2049833 |
| Iterations | 3 |
| Avg time | 11.585 sec |
| Min/Max time | 10.229 / 12.950 sec |
| Throughput (nodes) | 176945 nodes/sec |
| Throughput (files) | 307.2 files/sec |
| Avg memory delta | +516741 KB |
| Avg time per file | 3.26 ms |
| Avg nodes per file | 575 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.479 ms |
| Max | 0.479 ms |
| Avg | 0.479 ms |
| Median (p50) | 0.479 ms |
| p95 | 0.479 ms |
| p99 | 0.479 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 3.527 sec |
| Throughput | 567 inferences/sec |
| Min | 0.001 ms |
| Max | 185.004 ms |
| Avg | 1.764 ms |
| Median (p50) | 0.051 ms |
| p95 | 5.993 ms |
| p99 | 36.005 ms |


## Performance Summary

- **Indexing**: 176945 nodes/sec (307.2 files/sec)
- **Inference**: 567 inferences/sec (1.764 ms/inference)

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
