# TypeGuessr Benchmark Report

Generated: 2026-01-07 22:25:19

## Configuration

- **Target:** all
- **Files:** 3565
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3565 |
| Total nodes | 569418 |
| Total time | 14.008 sec |
| Throughput (nodes) | 40648 nodes/sec |
| Throughput (files) | 254.5 files/sec |
| Memory delta | +450244 KB |
| Avg time per file | 3.93 ms |
| Avg nodes per file | 159 |


## Inference Results

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Nodes inferred | 2000 |
| Total time | 3.598 sec |
| Throughput | 556 inferences/sec |
| Avg per inference | 1.799 ms |


## Performance Summary

- **Indexing**: 40648 nodes/sec (254.5 files/sec)
- **Inference**: 556 inferences/sec (1.799 ms/inference)

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
