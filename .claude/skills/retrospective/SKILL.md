---
name: retrospective
description: Extract and preserve reusable knowledge from the current session (project)
---

# Retrospective Knowledge Extraction

Extract reusable knowledge from the current conversation and update the Knowledge Base section in CLAUDE.md.

## When to Use

Invoke `/retro` at the end of a productive session when you want to preserve:
- Architecture insights discovered
- Coding patterns that proved useful
- Tool commands and debugging techniques
- Naming conventions or style decisions

## Process

### Step 1: Read Current Session

Run the following command to read the conversation history:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" read-session
```

Review the output and identify knowledge worth preserving.

### Step 2: Identify Knowledge Categories

Look for insights in these categories:

| Category | Prefix | Examples |
|----------|--------|----------|
| Architecture | `arch` | System design decisions, component relationships |
| Pattern | `pat` | Reusable code patterns, idioms, testing patterns |
| Tool | `tool` | Useful commands, debugging techniques |
| Convention | `conv` | Naming rules, code organization standards |

### Step 3: Check Existing Knowledge

List current entries to avoid duplicates:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" list
```

### Step 4: Add New Knowledge

For each new piece of knowledge:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" add -c <category> -t "<content>"
```

Example:
```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" add -c pat -t "Use guard clauses for early returns to reduce nesting"
```

### Step 5: Update Scores for Referenced Knowledge

If you used knowledge from the Knowledge Base during this session that was helpful:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" helpful <entry-id>
```

If any knowledge was misleading or harmful:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" harmful <entry-id>
```

### Step 6: Cleanup

Remove stale or harmful entries:

```bash
.claude/skills/retro/scripts/knowledge-manager --project-path "$(pwd)" cleanup
```

## Entry Guidelines

### Good Knowledge Entry

- **Specific:** References actual project elements (classes, files, methods)
- **Actionable:** Someone could apply this immediately
- **Non-obvious:** Not something a developer would guess
- **Verified:** Discovered through actual work, not assumption

### Examples

Good:
- `arch-001: LocationIndex uses file-scoped storage for O(1) node removal on file changes`
- `pat-001: Variable node types share common interface: dependencies, node_hash, node_key methods`
- `tool-001: Debug type inference with TYPE_GUESSR_DEBUG=1 bundle exec rspec <file>`

Bad (too vague):
- `Use classes for nodes`
- `Run tests before commit`

## Score Interpretation

| Score | Meaning |
|-------|---------|
| `[+n, -0, date]` | Helpful n times |
| `[+n, -m, date]` | Helpful n times, harmful m times |
| `[+0, -n, date]` | Harmful n times (consider removal) |
| `[+0, -0, date]` | New, unverified |

Entries are automatically removed if:
- `harmful >= 3`
- `helpful == 0` and age > 60 days
