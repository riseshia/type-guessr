# TypeGuessr Coverage Report

Generated: 2026-01-24 10:53:13

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3330 |
| Node Coverage | 46.1% (308650/669931) |
| Signature Score | 0.36 |
| Project Methods | 40884 |

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| CallNode | 23.8% | 42491/178229 |
| LiteralNode | 100.0% | 124256/124256 |
| LocalReadNode | 18.9% | 21744/114750 |
| ParamNode | 12.5% | 8167/65225 |
| SelfNode | 100.0% | 55873/55873 |
| LocalWriteNode | 41.9% | 10789/25759 |
| MergeNode | 98.8% | 25174/25489 |
| ConstantNode | 9.4% | 1831/19538 |
| InstanceVariableReadNode | 29.9% | 5557/18578 |
| ClassModuleNode | 0.0% | 0/12049 |
| InstanceVariableWriteNode | 50.7% | 6002/11838 |
| BlockParamSlot | 6.4% | 699/10880 |
| ReturnNode | 81.2% | 6035/7432 |
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
