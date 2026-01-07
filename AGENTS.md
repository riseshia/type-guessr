# TypeGuessr - Project Context

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

## Project Structure

```
type-guessr/
├── .github/
│   └── workflows/                               # GitHub Actions CI configuration
├── bin/
│   ├── console
│   ├── gen-doc                                  # Documentation generator
│   └── setup
├── lib/
│   ├── type-guessr.rb                           # Main entry point
│   ├── ruby_lsp/
│   │   └── type_guessr/
│   │       ├── addon.rb                         # LSP addon registration
│   │       ├── config.rb                        # Configuration management
│   │       ├── debug_server.rb                  # Debug web server
│   │       ├── hover.rb                         # Hover provider
│   │       └── runtime_adapter.rb               # Runtime management
│   └── type_guessr/
│       ├── version.rb                           # Version constant
│       └── core/
│           ├── converter/
│           │   ├── prism_converter.rb           # Prism AST → Node graph
│           │   └── rbs_converter.rb             # RBS → Internal types
│           ├── index/
│           │   └── location_index.rb            # Node lookup index
│           ├── inference/
│           │   ├── resolver.rb                  # Type resolution
│           │   └── result.rb                    # Inference result
│           ├── ir/
│           │   └── nodes.rb                     # Node definitions
│           ├── logger.rb                        # Logger utility
│           ├── rbs_provider.rb                  # RBS method signatures
│           └── types.rb                         # Type system
├── spec/
│   ├── spec_helper.rb
│   ├── integration/
│   │   ├── hover_spec.rb                        # Integration tests for hover
│   │   └── ir_hover_spec.rb                     # Node-based hover tests
│   ├── ruby_lsp/
│   │   ├── addon_loading_spec.rb
│   │   ├── enabled_config_spec.rb
│   │   └── guesser_spec.rb
│   ├── support/
│   │   └── doc_collector.rb                     # Documentation collection helper
│   └── type_guessr/
│       └── core/
│           ├── converter/
│           │   ├── prism_converter_spec.rb
│           │   └── rbs_converter_spec.rb
│           ├── index/
│           │   └── location_index_spec.rb
│           ├── inference/
│           │   ├── resolver_spec.rb
│           │   └── result_spec.rb
│           ├── ir/
│           │   └── nodes_spec.rb
│           ├── logger_spec.rb
│           ├── rbs_provider_spec.rb
│           └── types_spec.rb
├── docs/
│   ├── architecture.md                          # Architecture documentation
│   └── inference_rules.md                       # Generated inference rules
├── .rspec                                       # RSpec configuration
├── .rubocop.yml                                 # RuboCop configuration
├── AGENTS.md                                    # Project context for AI agents
├── Gemfile
├── todo.md                                      # Task tracking and priorities
├── README.md
└── type-guessr.gemspec                          # Gem specification
```

## Core Components

### Architecture Overview

The project is organized into two main layers:
- **Core (`TypeGuessr::Core`)**: Framework-agnostic type inference logic
- **Integration (`lib/ruby_lsp/type_guessr/`)**: Ruby LSP-specific adapter layer

### Core Layer (`lib/type_guessr/core/`)

#### 1. Nodes (`ir/nodes.rb`)
- Defines node types for the dependency graph
- Each node points to nodes it depends on for type inference
- Types: `LiteralNode`, `VariableNode`, `ParamNode`, `CallNode`, `DefNode`, `MergeNode`, etc.

#### 2. PrismConverter (`converter/prism_converter.rb`)
- Converts Prism AST to node graph at indexing time
- Tracks variable definitions via Context
- Handles method calls and indexed assignments

#### 3. RBSConverter (`converter/rbs_converter.rb`)
- Converts RBS types to internal type system
- Isolates RBS dependencies from core inference logic

#### 4. LocationIndex (`index/location_index.rb`)
- O(1) lookup from node key to node
- Per-file storage for efficient file removal

#### 5. Resolver (`inference/resolver.rb`)
- Resolves nodes to types by traversing the dependency graph
- Caches inference results per node
- Handles RBS method signature lookup

#### 6. Types (`types.rb`)
- Type representations: `ClassInstance`, `ArrayType`, `HashType`, `HashShape`, `Union`, `Unknown`, etc.

#### 7. RBSProvider (`rbs_provider.rb`)
- Provides RBS method signatures and return types
- Handles type variable substitution for generics

### Integration Layer (`lib/ruby_lsp/type_guessr/`)

#### 1. Addon (`addon.rb`)
- Registers the addon with Ruby LSP
- Extends hover targets to support additional node types
- Handles file change notifications

#### 2. RuntimeAdapter (`runtime_adapter.rb`)
- Manages the node graph and inference
- Handles file indexing and re-indexing
- Provides thread-safe access to inference results

#### 3. Hover (`hover.rb`)
- Provides type information on hover
- Uses node key lookup for fast node retrieval
- Formats hover content with type links

#### 4. Config (`config.rb`)
- Configuration management
- Reads from `.type-guessr.yml` or environment variables

#### 5. DebugServer (`debug_server.rb`)
- HTTP server for inspecting index data
- Only runs when debug mode is enabled

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
3. Regenerate docs if `spec/integration/hover_spec.rb` was modified: `bin/gen-doc`
4. Make ONE atomic commit

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

Tests tagged with `:doc` are automatically included in `docs/inference_rules.md`.

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

### Project Understanding

- **Project Goal:** Heuristic type inference for enhanced Go to Definition and hover
- **Core Philosophy:** Pragmatic type hints over perfect accuracy
- **Two-layer architecture:** Core (framework-agnostic) + Integration (Ruby LSP-specific)

### Development Process

- **TDD is mandatory:** Follow Red-Green-Refactor cycle
- **Linter-first:** Run `bundle exec rubocop -a` on changed files BEFORE committing
- **Atomic commits:** Group related changes into single commits
- **AST traversal:** When working with Prism nodes, be careful with node types and methods

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
