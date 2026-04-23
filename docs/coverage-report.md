# TypeGuessr Coverage Report

Generated: 2026-04-24 07:30:11

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3832 |
| Node Coverage | 79.6% (1770909/2223899) |
| Inference Coverage | 40.1% (303594/756584) |
| Signature Score | 0.39 |
| Project Methods | 48449 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1460148/1460148 |
| CallNode | 37.4% | 109623/293237 |
| LocalReadNode | 36.6% | 61309/167678 |
| ParamNode | 20.8% | 15194/72893 |
| LocalWriteNode | 54.5% | 24055/44123 |
| MergeNode | 53.5% | 22494/42042 |
| ConstantNode | 50.3% | 21030/41841 |
| InstanceVariableReadNode | 78.0% | 18989/24349 |
| ReturnNode | 83.2% | 15591/18733 |
| BlockParamSlot | 19.3% | 3334/17261 |
| InstanceVariableWriteNode | 55.3% | 9063/16401 |
| ClassModuleNode | 0.0% | 0/13542 |
| SelfNode | 100.0% | 7167/7167 |
| OrNode | 64.1% | 2770/4321 |
| ClassVariableWriteNode | 84.1% | 74/88 |
| ClassVariableReadNode | 90.7% | 68/75 |

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
