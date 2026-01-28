# TypeGuessr Coverage Report

Generated: 2026-01-28 22:02:10

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3331 |
| Node Coverage | 46.1% (308749/670195) |
| Signature Score | 0.36 |
| Project Methods | 40907 |

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| CallNode | 23.8% | 42499/178306 |
| LiteralNode | 100.0% | 124283/124283 |
| LocalReadNode | 19.0% | 21761/114801 |
| ParamNode | 12.5% | 8175/65249 |
| SelfNode | 100.0% | 55878/55878 |
| LocalWriteNode | 41.8% | 10785/25771 |
| MergeNode | 98.8% | 25198/25504 |
| ConstantNode | 9.4% | 1832/19548 |
| InstanceVariableReadNode | 29.9% | 5557/18590 |
| ClassModuleNode | 0.0% | 0/12052 |
| InstanceVariableWriteNode | 50.7% | 6007/11846 |
| BlockParamSlot | 6.4% | 700/10891 |
| ReturnNode | 81.2% | 6042/7441 |
| ClassVariableReadNode | 92.3% | 24/26 |
| ClassVariableWriteNode | 88.9% | 8/9 |

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
