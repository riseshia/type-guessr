# TypeGuessr Coverage Report

Generated: 2026-01-29 20:51:50

## Summary

| Metric | Value |
|--------|-------|
| Files Analyzed | 3331 |
| Node Coverage | 46.3% (310454/670614) |
| Signature Score | 0.36 |
| Project Methods | 40930 |

## Node Coverage Breakdown

| Node Type | Coverage | Typed/Total |
|-----------|----------|-------------|
| CallNode | 24.3% | 43415/178444 |
| LiteralNode | 100.0% | 124331/124331 |
| LocalReadNode | 19.1% | 21955/114888 |
| ParamNode | 12.6% | 8207/65279 |
| SelfNode | 100.0% | 55915/55915 |
| LocalWriteNode | 42.2% | 10880/25783 |
| MergeNode | 100.0% | 25508/25512 |
| ConstantNode | 9.4% | 1836/19572 |
| InstanceVariableReadNode | 29.9% | 5560/18613 |
| ClassModuleNode | 0.0% | 0/12055 |
| InstanceVariableWriteNode | 50.9% | 6028/11854 |
| BlockParamSlot | 6.7% | 731/10895 |
| ReturnNode | 81.4% | 6056/7438 |
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
