# TypeGuessr Coverage Report

Generated: 2026-03-15 21:59:06

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3796 |
| Node Coverage | 79.1% (1758966/2224073) |
| Inference Coverage | 38.2% (288041/753148) |
| Signature Score | 0.38 |
| Project Methods | 43080 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1463789/1463789 |
| CallNode | 32.7% | 96169/294427 |
| LocalReadNode | 36.5% | 60624/165923 |
| ParamNode | 20.8% | 15060/72355 |
| LocalWriteNode | 54.4% | 23762/43699 |
| MergeNode | 53.2% | 22057/41483 |
| ConstantNode | 50.9% | 21099/41444 |
| InstanceVariableReadNode | 77.3% | 18748/24254 |
| ReturnNode | 83.1% | 15373/18509 |
| BlockParamSlot | 19.7% | 3369/17064 |
| InstanceVariableWriteNode | 54.9% | 8897/16201 |
| ClassModuleNode | 0.0% | 0/13409 |
| SelfNode | 100.0% | 7136/7136 |
| OrNode | 65.1% | 2747/4222 |
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
