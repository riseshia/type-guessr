# TypeGuessr Benchmark Report

Generated: 2026-01-10 15:09:24

## Configuration

- **Target:** all
- **Files:** 3574
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3574 |
| Total nodes | 576878 |
| Iterations | 3 |
| Avg time | 11.299 sec |
| Min/Max time | 11.062 / 11.499 sec |
| Throughput (nodes) | 51058 nodes/sec |
| Throughput (files) | 316.3 files/sec |
| Avg memory delta | +238144 KB |
| Avg time per file | 3.16 ms |
| Avg nodes per file | 161 |


## Inference Results

| Metric | Value |
|--------|-------|
| Nodes sampled | 2000 |
| Nodes inferred | 2000 |
| Total time | 3.356 sec |
| Throughput | 596 inferences/sec |
| Avg per inference | 1.678 ms |


## Performance Summary

- **Indexing**: 51058 nodes/sec (316.3 files/sec)
- **Inference**: 596 inferences/sec (1.678 ms/inference)

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
