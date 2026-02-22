# TypeGuessr - Project Context

## Behavioral Rules

### Measure, Don't Estimate
- When numbers are needed (performance, memory, file counts), run actual measurements locally
- Prefer local execution over internet searches for empirical data
- Measurements without code_index are meaningless — code_index is required for all inference-related benchmarks

### Prioritization
- CI/test failures > fixing existing features > new features
- After context resumption, re-read brain.md and confirm the current task before starting work
- Only work on what the user requested. Do not start related tasks without asking

### Action Over Explanation
- When the user points out a problem, propose a fix immediately — the user already knows the problem
- Do not dismiss test failures as "pre-existing" without first investigating whether your changes could be the cause
- Propose fixing existing implementations before suggesting to scrap them
- Execute promised actions (todo.md updates, file additions) immediately — do not defer

### Context Management
- In long sessions, persist important intermediate results to files (they survive compaction)
- When presenting sub-agent results, assume the user has NOT read the raw output
- After context compaction, re-read brain.md and todo.md to recover state

### Critical Invariants
- NEVER pass code_index as nil — inheritance chains, duck typing, and type simplification all depend on it
- NEVER deploy performance-sensitive features without benchmarking on representative workloads first
- NEVER introduce concurrent access to shared data structures without considering thread-safety

## Project Overview

TypeGuessr is a Ruby LSP addon that provides **heuristic type inference** without requiring explicit type annotations. The goal is to achieve a "useful enough" development experience by prioritizing practical type hints over perfect accuracy.

**Core Approach:**
- Infers types from **method call patterns** (inspired by duck typing)
- Hooks into ruby-lsp's TypeInferrer to enhance Go to Definition and other features
- Uses variable naming conventions as hints
- Leverages RBS definitions when available
- Focuses on pragmatic developer experience rather than type correctness

**Key Example:**
```ruby
def fetch_comments(recipe)
  recipe.comments  # If 'comments' method exists only in Recipe class,
end                # infer recipe type as Recipe instance
```

**Key Information:**
- **Language:** Ruby 3.3.0+
- **Type:** Ruby LSP Addon (Gem)
- **Main Dependency:** ruby-lsp ~> 0.22
- **Author:** riseshia
- **Repository:** https://github.com/riseshia/type-guessr

## Development Workflow

### Setup
```bash
bin/setup
```

### Running Tests
```bash
bundle exec rspec
```

### Running Linter
```bash
bundle exec rubocop -a
```

### Running All Checks
```bash
bundle exec rspec && bundle exec rubocop -a
```

### Console
```bash
bin/console
```

### Testing Hover in Real LSP Environment
```bash
bin/hover-repl
```

REPL-style tool that spawns actual ruby-lsp server with TypeGuessr addon.
Waits for full project indexing (~20 seconds), then allows multiple hover queries:

```
> lib/ruby_lsp/type_guessr/config.rb 40 11
**Method Signature:** `() -> ?Hash[String, true | false]`
...
> exit
```

**Non-interactive mode** (for Claude Code debugging):
```bash
# Single query - outputs hover result and exits
bin/hover-repl lib/ruby_lsp/type_guessr/config.rb 40 11

# JSON output for programmatic use
bin/hover-repl lib/ruby_lsp/type_guessr/config.rb 40 11 --json
```

Use this to verify hover results match what users see in their editors.

## TDD Development Workflow

This project follows strict Test-Driven Development (TDD) practices.

### TDD Cycle: Red → Green → Refactor

1. **Red:** Write a failing test first
2. **Green:** Write minimal code to make the test pass
3. **Refactor:** Clean up code while keeping tests green
4. **Commit:** Only commit when all tests pass

## Important Conventions

1. **Language:** **ALL code-related content MUST be written in English:**
   - Commit messages, code comments, variable names, documentation
   - **Exception:** You may communicate with the user in Korean for clarifications

2. **Frozen String Literals:** All Ruby files use `# frozen_string_literal: true`

3. **Code Style:** Follows RuboCop rules defined in `.rubocop.yml`

4. **Testing:** Uses RSpec for testing

5. **Naming:**
   - Module: `TypeGuessr` (core), `RubyLsp::TypeGuessr` (LSP integration)
   - Gem: `type-guessr`

## Before Making Changes

**Pre-Commit Checklist:**

1. Run linter on changed files: `bundle exec rubocop -a <changed_files>`
2. Run all tests: `bundle exec rspec`
3. Regenerate docs if any `:doc` tagged integration specs were modified: `bin/gen-doc`
4. If any of the following files were changed, suggest running `/sync-docs`:
   - `lib/type_guessr/core/types.rb` (Type additions/removals)
   - `lib/type_guessr/core/ir/nodes.rb` (IR Node additions/removals)
   - `lib/type_guessr/core/registry/` (registry structure changes)
   - `lib/type_guessr/core/index/` (index mechanism changes)
   - `lib/ruby_lsp/type_guessr/` (new integration files)
5. Make ONE atomic commit

## Commit Strategy

**Always group related changes into single commits:**

✅ **Good** - Single commit:
```
"Add method call tracking for type inference"
- Implement feature
- Fix RuboCop violations
- Add test cases
```

❌ **Bad** - Multiple commits:
```
"Add method call tracking"
"Fix rubocop violations"
"Add tests"
```

## Configuration

Configuration is done via `.type-guessr.yml` in the project root:

```yaml
# .type-guessr.yml
enabled: true
debug: true
debug_server: false  # optional: disable debug server while keeping debug logging
```

**Debug mode features:**
- Enables debug logging to stderr
- Shows inference basis in hover UI
- Starts debug web server (unless `debug_server: false`)

## Generating Documentation

```bash
bin/gen-doc
```

Tests tagged with `:doc` in integration specs are automatically included in documentation files under `docs/` (e.g., `class.md`, `container.md`, `control.md`, `literal.md`, `variable.md`).

## Type Inference Strategy

### Method Call Pattern Collection

1. RuntimeAdapter starts background AST traversal after ruby-lsp's initial indexing completes
2. PrismConverter converts files to node graphs
3. LocationIndex stores nodes for fast lookup

### Heuristic Type Inference

Type guessing is performed through:

1. **Direct type detection:**
   - Literal assignments (strings, integers, arrays, etc.)
   - `.new` calls → infer class type

2. **Method name uniqueness analysis:**
   - If `recipe.comments` is found and `comments` method exists only in `Recipe` class → infer `recipe` type as `Recipe`

3. **RBS integration:**
   - Use RBS definitions for stdlib and gem types
   - Fill gaps with heuristic inference

## Notes for Claude

### Architecture Decision Records (ADR)

Before proposing design or architectural changes, **check `docs/adr/` for existing decisions**.
If proposing changes that conflict with an ADR, discuss with the user first.

### Project Understanding

- **Project Goal:** Heuristic type inference for enhanced Go to Definition and hover
- **Core Philosophy:** Pragmatic type hints over perfect accuracy
- **Two-layer architecture:** Core (framework-agnostic) + Integration (Ruby LSP-specific)

### Development Process

- **TDD is mandatory:** Follow Red-Green-Refactor cycle
- **Linter-first:** Run `bundle exec rubocop -a` on changed files BEFORE committing
- **Atomic commits:** Group related changes into single commits
- **AST traversal:** When working with Prism nodes, be careful with node types and methods

### Testing

When implementing changes across IR nodes or similar parallel structures, always check ALL spec files that might reference the modified interfaces (resolver_spec, method_registry_spec, graph_builder_spec, signature_builder_spec, location_index_spec, etc.)

### IR Node Architecture

When adding fields to IR nodes, verify if any nodes share state with others (e.g., LocalReadNode shares called_methods with BlockParamSlot) before implementing.

### Design Decisions

For Ruby/Rails type inference work, consider ruby-lsp-rails integration points when designing DSL handling.

### TodoWrite Usage

**Skip TodoWrite for simple tasks** (single file, 1-2 steps, simple fixes)

**Use TodoWrite only for complex tasks:**
- 3+ distinct files need changes
- Multiple independent systems affected
- Complex multi-step requiring research + design + implementation

### Parallel Execution

**ALWAYS execute operations in parallel when there are no dependencies:**

✅ **Must parallelize:**
- Reading multiple files: `Read(file1.rb) + Read(file2.rb)` together
- Git inspection: `git status + git diff + git log` together

❌ **Only sequential when TRUE dependencies exist:**
- Edit needs Read first
- Commit needs tests to pass first

### Coding Guidelines

**Think Before Coding:**
- State assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.

**Simplicity First:**
- No features beyond what was asked.
- No abstractions for single-use code.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

**Surgical Changes:**
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

**Goal-Driven Execution:**
- Transform tasks into verifiable goals with success criteria.
- For multi-step tasks, state a brief plan with verification steps.
