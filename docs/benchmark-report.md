# TypeGuessr Benchmark Report

Generated: 2026-02-23 10:38:28

## Configuration

- **Target:** all
- **Files:** 3724
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3724 |
| Total nodes | 2132065 |
| Iterations | 3 |
| Avg time | 14.223 sec |
| Min/Max time | 13.553 / 15.509 sec |
| Throughput (nodes) | 149901 nodes/sec |
| Throughput (files) | 261.8 files/sec |
| Avg memory delta | +558106 KB |
| Avg time per file | 3.82 ms |
| Avg nodes per file | 572 |


## Inference Results

### File Open (first inference per file)

| Metric | Value |
|--------|-------|
| Files measured | 1 |
| Min | 0.163 ms |
| Max | 0.163 ms |
| Avg | 0.163 ms |
| Median (p50) | 0.163 ms |
| p95 | 0.163 ms |
| p99 | 0.163 ms |

### Warm (subsequent inferences)

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Total inferred | 2000 |
| Total time | 3.309 sec |
| Throughput | 604 inferences/sec |
| Min | 0.001 ms |
| Max | 117.523 ms |
| Avg | 1.655 ms |
| Median (p50) | 0.044 ms |
| p95 | 7.126 ms |
| p99 | 27.335 ms |


## Performance Summary

- **Indexing**: 149901 nodes/sec (261.8 files/sec)
- **Inference**: 604 inferences/sec (1.654 ms/inference)

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
