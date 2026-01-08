# TypeGuessr Benchmark Report

Generated: 2026-01-08 14:17:08

## Configuration

- **Target:** indexing
- **Files:** 3572
- **Warmup:** 2s
- **Benchmark time:** 5s
- **Inference samples:** 2000

---

## Indexing Results

| Metric | Value |
|--------|-------|
| Files indexed | 3572 |
| Total nodes | 576310 |
| Iterations | 3 |
| Avg time | 11.588 sec |
| Min/Max time | 11.005 / 12.121 sec |
| Throughput (nodes) | 49735 nodes/sec |
| Throughput (files) | 308.3 files/sec |
| Avg memory delta | +233500 KB |
| Avg time per file | 3.24 ms |
| Avg nodes per file | 161 |




## Performance Summary

- **Indexing**: 49735 nodes/sec (308.3 files/sec)

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
