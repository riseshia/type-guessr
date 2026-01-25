---
description: Measure TypeGuessr type inference coverage on a codebase
allowed-tools: Bash(bin/coverage:*), Read
---

## Context

TypeGuessr self-coverage analysis - measures how well type inference is working across a codebase.

## Your task

Run coverage analysis and report the results.

### Step 1: Run Coverage Analysis

Run the coverage report:

```bash
bin/coverage
```

### Step 2: Analyze Results

Review the output metrics:

1. **Node Coverage:**
   - Overall percentage of nodes with inferred types
   - Breakdown by node type (ParamNode, CallNode, etc.)
   - Identify which node types have lowest coverage

2. **Signature Score:**
   - Average method signature completeness (0.0 - 1.0)
   - Number of project methods analyzed

### Step 3: Report Summary

Summarize findings:

1. **Overall coverage** percentage
2. **Weakest areas** (node types with lowest coverage)
3. **Signature completeness** score
4. **Recommendations** for improving type inference

## Available Options

```
--path=PATH                 Project directory to analyze (default: current)
--report                    Generate markdown report to docs/coverage-report.md
--json                      Output in JSON format
--dump-untyped[=TYPES]      Dump untyped nodes to tmp/untyped_nodes.json
--limit=N                   Limit number of dumped untyped nodes
```

## Quick Commands

```bash
# Basic coverage report
bin/coverage

# Generate markdown report
bin/coverage --report

# JSON output for scripting
bin/coverage --json

# Analyze a different project
bin/coverage --path=/path/to/project

# Dump untyped nodes for analysis
bin/coverage --dump-untyped --limit=100

# Dump only untyped ParamNodes
bin/coverage --dump-untyped=ParamNode --limit=50

# Analyze untyped nodes
cat tmp/untyped_nodes.json | jq '.nodes | group_by(.type) | map({type: .[0].type, count: length})'
```

## Interpreting Results

### Node Coverage Targets

| Node Type | Good | Needs Work |
|-----------|------|------------|
| LiteralNode | 100% | < 100% |
| SelfNode | 100% | < 100% |
| LocalWriteNode | > 50% | < 30% |
| ParamNode | > 20% | < 10% |
| CallNode | > 30% | < 15% |

### Signature Score

- **1.0**: All method signatures fully typed
- **> 0.5**: Good coverage
- **< 0.3**: Significant room for improvement
