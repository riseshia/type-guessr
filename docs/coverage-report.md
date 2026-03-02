# TypeGuessr Coverage Report

Generated: 2026-03-02 20:51:29

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3725 |
| Node Coverage | 79.2% (1754592/2214241) |
| Inference Coverage | 38.3% (285474/745123) |
| Signature Score | 0.38 |
| Project Methods | 43020 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1462291/1462291 |
| CallNode | 32.7% | 95315/291161 |
| LocalReadNode | 36.7% | 59848/163101 |
| ParamNode | 20.9% | 15005/71859 |
| LocalWriteNode | 54.3% | 23634/43500 |
| MergeNode | 53.0% | 21893/41278 |
| ConstantNode | 50.5% | 20747/41059 |
| InstanceVariableReadNode | 77.3% | 18699/24196 |
| ReturnNode | 83.1% | 15340/18450 |
| BlockParamSlot | 19.6% | 3257/16651 |
| InstanceVariableWriteNode | 54.9% | 8881/16173 |
| ClassModuleNode | 0.0% | 0/13345 |
| SelfNode | 100.0% | 6827/6827 |
| OrNode | 64.9% | 2719/4192 |
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
