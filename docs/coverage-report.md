# TypeGuessr Coverage Report

Generated: 2026-03-10 21:56:34

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3755 |
| Node Coverage | 79.2% (1755157/2215723) |
| Inference Coverage | 38.3% (285672/746238) |
| Signature Score | 0.38 |
| Project Methods | 43153 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1462656/1462656 |
| CallNode | 32.7% | 95352/291692 |
| LocalReadNode | 36.7% | 59868/163319 |
| ParamNode | 20.9% | 15020/71887 |
| LocalWriteNode | 54.2% | 23647/43629 |
| MergeNode | 53.0% | 21900/41292 |
| ConstantNode | 50.7% | 20875/41193 |
| InstanceVariableReadNode | 77.2% | 18685/24202 |
| ReturnNode | 83.1% | 15344/18456 |
| BlockParamSlot | 19.4% | 3242/16674 |
| InstanceVariableWriteNode | 54.9% | 8879/16176 |
| ClassModuleNode | 0.0% | 0/13363 |
| SelfNode | 100.0% | 6829/6829 |
| OrNode | 64.9% | 2724/4197 |
| ClassVariableWriteNode | 82.1% | 69/84 |
| ClassVariableReadNode | 90.5% | 67/74 |

## Metrics Explanation

### Node Coverage
Percentage of IR nodes with successfully inferred types. DefNode is excluded to avoid double-counting (its params and return are counted separately).

### Signature Score
Average of (typed_slots / total_slots) for each project method. Slots include all parameters plus the return type. A score of 1.0 means all method signatures are fully typed.

---

## How to Use

```bash
# Run coverage report
bin/coverage

# Generate markdown report
bin/coverage --report

# Output as JSON
bin/coverage --json

# Analyze a different project
bin/coverage --path=/path/to/project
```
