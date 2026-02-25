# TypeGuessr Coverage Report

Generated: 2026-02-25 18:19:43

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3723 |
| Node Coverage | 79.2% (1755815/2216495) |
| Inference Coverage | 38.2% (285255/745935) |
| Signature Score | 0.38 |
| Project Methods | 42704 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1463722/1463722 |
| CallNode | 32.4% | 95028/292872 |
| LocalReadNode | 37.0% | 60261/163061 |
| ParamNode | 21.1% | 15041/71422 |
| LocalWriteNode | 54.0% | 23606/43711 |
| ConstantNode | 50.3% | 20758/41307 |
| MergeNode | 52.8% | 21567/40822 |
| InstanceVariableReadNode | 77.8% | 19054/24500 |
| ReturnNode | 82.7% | 14813/17914 |
| BlockParamSlot | 20.3% | 3374/16581 |
| InstanceVariableWriteNode | 55.3% | 8931/16151 |
| ClassModuleNode | 0.0% | 0/13291 |
| SelfNode | 100.0% | 6838/6838 |
| OrNode | 64.8% | 2686/4145 |
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
