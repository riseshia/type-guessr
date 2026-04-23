# TypeGuessr Benchmark Report

Generated: 2026-04-24 07:28:40

## Configuration

- **Target:** all
- **Files:** 3832
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3832 |
| Total nodes | 2145320 |
| Iterations | 3 |
| Avg time | 9.234 sec |
| Min/Max time | 8.748 / 10.104 sec |
| Throughput (nodes) | 232332 nodes/sec |
| Throughput (files) | 415.0 files/sec |
| Avg memory delta | +575578 KB |
| Avg time per file | 2.41 ms |
| Avg nodes per file | 559 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.110 ms |
| Max | 0.110 ms |
| Avg | 0.110 ms |
| Median (p50) | 0.110 ms |
| p95 | 0.110 ms |
| p99 | 0.110 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 2.595 sec |
| Throughput | 771 inferences/sec |
| Min | 0.000 ms |
| Max | 88.817 ms |
| Avg | 1.298 ms |
| Median (p50) | 0.018 ms |
| p95 | 5.726 ms |
| p99 | 24.430 ms |


## Performance Summary

- **Indexing**: 232332 nodes/sec (415.0 files/sec)
- **Inference**: 771 inferences/sec (1.297 ms/inference)

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
