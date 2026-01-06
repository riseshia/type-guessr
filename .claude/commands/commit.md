---
description: Create a git commit with auto-generated message
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*)
---

## Step 1: Knowledge Extraction

First, use the `retrospective` skill to extract any reusable knowledge from this session before committing.

## Step 2: Create Commit

### Context

- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -5`
- Current git status: !`git status --short`
- Staged changes: !`git diff --cached`
- Unstaged changes: !`git diff`

## Your task

Based on the above changes:

1. Review the staged and unstaged changes
2. If there are unstaged changes that should be included, stage them with `git add`
3. Write a concise commit message that:
   - Summarizes the "why" rather than the "what"
   - Follows the style of recent commits
   - Is 1-2 sentences max
4. Create the commit with the message ending with:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

5. Show the final `git status` to confirm
