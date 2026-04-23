# TypeGuessr Coverage Report

Generated: 2026-04-23 14:09:37

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3804 |
| Node Coverage | 79.7% (1765878/2215532) |
| Inference Coverage | 39.9% (298833/748487) |
| Signature Score | 0.38 |
| Project Methods | 47574 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1459922/1459922 |
| CallNode | 36.9% | 107688/291619 |
| LocalReadNode | 36.7% | 60744/165604 |
| ParamNode | 21.0% | 15056/71824 |
| LocalWriteNode | 53.9% | 23610/43802 |
| ConstantNode | 50.2% | 20905/41628 |
| MergeNode | 53.4% | 21802/40843 |
| InstanceVariableReadNode | 78.1% | 19199/24576 |
| ReturnNode | 82.7% | 14748/17841 |
| BlockParamSlot | 19.7% | 3342/16952 |
| InstanceVariableWriteNode | 55.2% | 8921/16147 |
| ClassModuleNode | 0.0% | 0/13352 |
| SelfNode | 100.0% | 7123/7123 |
| OrNode | 64.7% | 2676/4136 |
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
