# TypeGuessr Coverage Report

Generated: 2026-04-19 08:17:44

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3559 |
| Node Coverage | 79.8% (1705763/2136430) |
| Inference Coverage | 37.5% (258181/688848) |
| Signature Score | 0.38 |
| Project Methods | 42315 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1441048/1441048 |
| CallNode | 31.7% | 86181/271943 |
| LocalReadNode | 35.4% | 53554/151397 |
| ParamNode | 20.3% | 13922/68468 |
| LocalWriteNode | 55.0% | 21388/38868 |
| MergeNode | 54.0% | 20211/37415 |
| ConstantNode | 51.4% | 18539/36099 |
| InstanceVariableReadNode | 78.6% | 16811/21384 |
| ReturnNode | 86.8% | 14512/16713 |
| BlockParamSlot | 18.6% | 2896/15542 |
| InstanceVariableWriteNode | 53.7% | 7601/14150 |
| ClassModuleNode | 0.0% | 0/12823 |
| SelfNode | 100.0% | 6534/6534 |
| OrNode | 62.6% | 2445/3904 |
| ClassVariableWriteNode | 81.3% | 61/75 |
| ClassVariableReadNode | 89.6% | 60/67 |

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
