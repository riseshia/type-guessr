# TypeGuessr Benchmark Report

Generated: 2026-01-28 22:00:48

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
| Total nodes | 800829 |
| Iterations | 3 |
| Avg time | 14.774 sec |
| Min/Max time | 14.092 / 16.113 sec |
| Throughput (nodes) | 54205 nodes/sec |
| Throughput (files) | 225.5 files/sec |
| Avg memory delta | +462501 KB |
| Avg time per file | 4.44 ms |
| Avg nodes per file | 240 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.048 ms |
| Max | 0.048 ms |
| Avg | 0.048 ms |
| Median (p50) | 0.048 ms |
| p95 | 0.048 ms |
| p99 | 0.048 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 1998 |
| Total time | 0.064 sec |
| Throughput | 31322 inferences/sec |
| Min | 0.001 ms |
| Max | 6.545 ms |
| Avg | 0.032 ms |
| Median (p50) | 0.009 ms |
| p95 | 0.040 ms |
| p99 | 0.167 ms |


## Performance Summary

- **Indexing**: 54205 nodes/sec (225.5 files/sec)
- **Inference**: 31322 inferences/sec (0.032 ms/inference)

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
