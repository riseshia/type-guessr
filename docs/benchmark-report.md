# TypeGuessr Benchmark Report

Generated: 2026-01-28 22:52:00

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
| Total nodes | 1968587 |
| Iterations | 3 |
| Avg time | 13.023 sec |
| Min/Max time | 12.139 / 14.542 sec |
| Throughput (nodes) | 151161 nodes/sec |
| Throughput (files) | 255.8 files/sec |
| Avg memory delta | +530728 KB |
| Avg time per file | 3.91 ms |
| Avg nodes per file | 590 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.052 ms |
| Max | 0.052 ms |
| Avg | 0.052 ms |
| Median (p50) | 0.052 ms |
| p95 | 0.052 ms |
| p99 | 0.052 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 1998 |
| Total time | 0.067 sec |
| Throughput | 30027 inferences/sec |
| Min | 0.000 ms |
| Max | 6.986 ms |
| Avg | 0.033 ms |
| Median (p50) | 0.009 ms |
| p95 | 0.040 ms |
| p99 | 0.173 ms |


## Performance Summary

- **Indexing**: 151161 nodes/sec (255.8 files/sec)
- **Inference**: 30027 inferences/sec (0.033 ms/inference)

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
