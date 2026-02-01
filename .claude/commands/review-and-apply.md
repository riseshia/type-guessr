---
description: Review user's code changes based on conversation, lint fix, and commit
allowed-tools: Bash, Read, Edit, Glob, Grep
---

## Context

This skill reviews the user's manually written code changes based on the current conversation context, runs linting, and commits if everything is good.

## Your task

Review and apply the user's code changes following these steps:

### Step 1: Review Code Changes

1. Run `git diff` to see what the user changed
2. Compare against what was discussed in the conversation
3. Check for:
   - Logic errors or bugs
   - Missing edge cases discussed earlier
   - Deviations from the agreed approach
   - Typos or obvious mistakes

### Step 2: Report Issues (if any)

If you find problems:
- **Stop here** and report the issues clearly
- Explain what's wrong and suggest fixes
- Do NOT proceed to linting or committing

### Step 3: Run Linter (if no issues)

If the code looks good:
```bash
bundle exec rubocop -a <changed_files>
```

- Let rubocop auto-fix style issues
- If rubocop reports unfixable errors, report them to the user

### Step 4: Commit

If linting passes:
1. Stage the changed files (not CLAUDE.local.md)
2. Write a commit message that:
   - Summarizes what was implemented
   - Follows the project's commit style
   - Ends with the standard Co-Authored-By footer

### Output Format

Report your progress:
- ✅ Code review: [passed/issues found]
- ✅ Lint: [passed/fixed N issues/errors found]
- ✅ Commit: [commit hash and message summary]
