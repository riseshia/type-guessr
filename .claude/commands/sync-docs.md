---
description: Sync architecture.md and CLAUDE.md with current codebase
allowed-tools: Bash, Read, Glob, Grep, Edit
---

## Context

Manual documentation (`docs/architecture.md`, `CLAUDE.md`) drifts from code over time.
This command detects discrepancies and fixes them.

Auto-generated docs (`docs/class.md`, `docs/variable.md`, etc.) are handled by `bin/gen-doc` and are NOT in scope.

## Your task

### Step 1: Gather current code state

Run these in parallel:

1. `git diff --name-only HEAD~5..HEAD` to see recently changed source files
2. Read `docs/architecture.md`
3. Read `CLAUDE.md` (project structure + core components sections)

### Step 2: Read source files for comparison

Read the following source files to compare against docs:

**Types & IR:**
- `lib/type_guessr/core/types.rb` — all Type subclasses
- `lib/type_guessr/core/ir/nodes.rb` — all IR Node types

**Registry & Index:**
- `lib/type_guessr/core/registry/` — list files, check class names
- `lib/type_guessr/core/index/location_index.rb` — lookup mechanism

**Core utilities:**
- `lib/type_guessr/core/` — list files, check for unlisted modules

**Integration layer:**
- `lib/ruby_lsp/type_guessr/` — list files, check for unlisted modules

### Step 3: Check each section

For `docs/architecture.md`, verify:

| Section | Check against |
|---------|--------------|
| ASCII diagram (Types box) | All Type subclasses in `types.rb` |
| ASCII diagram (IR Nodes box) | All Node types in `nodes.rb` |
| ASCII diagram (bottom row) | Registry file names |
| Nodes table | All Node types with correct descriptions |
| LocationIndex description | Actual lookup mechanism (`find_by_key` vs `find`) |
| Registry descriptions | Actual class names and method signatures |
| Types table | All Type subclasses listed |
| Data Flow diagrams | Actual method call chains in `runtime_adapter.rb` |
| Thread Safety section | Actual synchronized method names |

For `CLAUDE.md`, verify:

| Section | Check against |
|---------|--------------|
| Project Structure tree | Actual file listing via `ls` |
| Core Components list | Actual classes and descriptions |

### Step 4: Apply fixes

For each discrepancy found:
1. State what's wrong (old value vs actual value)
2. Apply the fix using Edit tool
3. Keep changes minimal — only fix what's actually wrong

### Step 5: Report

Output a summary table:

```
## Sync Results

| File | Section | Change |
|------|---------|--------|
| architecture.md | Types table | Added FooType |
| CLAUDE.md | Project Structure | Added bar.rb |

Total: N fixes applied (or "All docs up to date")
```

If no discrepancies found, report "All docs up to date" and stop.
