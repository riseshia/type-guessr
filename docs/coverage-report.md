# TypeGuessr Coverage Report

Generated: 2026-02-23 10:34:20

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3724 |
| Node Coverage | 79.4% (1738846/2191312) |
| Inference Coverage | 37.6% (272363/724829) |
| Signature Score | 0.38 |
| Project Methods | 42701 |

> **Node Coverage** includes trivially-typed nodes (LiteralNode, SelfNode).
> **Inference Coverage** excludes them to reflect actual type inference capability.

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| LiteralNode | 100.0% | 1459687/1459687 |
| CallNode | 31.9% | 89856/282088 |
| LocalReadNode | 36.6% | 58547/160082 |
| ParamNode | 20.8% | 14857/71418 |
| LocalWriteNode | 53.8% | 23466/43600 |
| ConstantNode | 50.3% | 20576/40874 |
| MergeNode | 48.6% | 17397/35822 |
| InstanceVariableReadNode | 78.0% | 18823/24142 |
| ReturnNode | 82.7% | 14806/17908 |
| BlockParamSlot | 19.9% | 3300/16577 |
| InstanceVariableWriteNode | 54.9% | 8837/16111 |
| ClassModuleNode | 0.0% | 0/13231 |
| SelfNode | 100.0% | 6796/6796 |
| OrNode | 62.6% | 1765/2821 |
| ClassVariableWriteNode | 82.1% | 69/84 |
| ClassVariableReadNode | 90.1% | 64/71 |

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
