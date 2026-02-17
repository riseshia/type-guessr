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
│   ├── benchmark                                # Performance benchmarking tool
│   ├── console
│   ├── gen-doc                                  # Documentation generator
│   ├── hover-repl                               # Interactive hover testing
│   ├── profile                                  # Profiling tool
│   └── setup
├── exe/
│   └── type-guessr                              # CLI executable (mcp, version, help)
├── lib/
│   ├── type-guessr.rb                           # Main entry point
│   ├── ruby_lsp/
│   │   └── type_guessr/
│   │       ├── addon.rb                         # LSP addon registration
│   │       ├── config.rb                        # Configuration management
│   │       ├── debug_server.rb                  # Debug web server
│   │       ├── graph_builder.rb                 # Node graph construction
│   │       ├── hover.rb                         # Hover provider
│   │       ├── runtime_adapter.rb               # Runtime management
│   │       └── type_inferrer.rb                 # Type inference coordinator
│   └── type_guessr/
│       ├── version.rb                           # Version constant
│       ├── mcp/
│       │   ├── server.rb                        # MCP server (stdio transport)
│       │   └── standalone_runtime.rb            # Standalone inference runtime
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
│           ├── registry/
│           │   ├── method_registry.rb           # Project method storage
│           │   ├── signature_registry.rb        # Stdlib RBS signatures
│           │   └── variable_registry.rb         # Instance/class variable storage
│           ├── logger.rb                        # Logger utility
│           ├── signature_builder.rb             # Method signature generation
│           ├── type_simplifier.rb               # Type simplification
│           └── types.rb                         # Type system
├── spec/
│   ├── spec_helper.rb
│   ├── integration/
│   │   ├── class_spec.rb                        # Class-related inference tests
│   │   ├── container_spec.rb                    # Array/Hash inference tests
│   │   ├── control_spec.rb                      # Control flow inference tests
│   │   ├── gem_method_spec.rb                   # Gem method inference tests
│   │   ├── hover_spec.rb                        # Integration tests for hover
│   │   ├── literal_spec.rb                      # Literal type inference tests
│   │   └── variable_spec.rb                     # Variable inference tests
│   ├── ruby_lsp/
│   │   ├── addon_loading_spec.rb
│   │   ├── enabled_config_spec.rb
│   │   ├── guesser_spec.rb
│   │   ├── type_inferrer_spec.rb
│   │   └── type_guessr/
│   │       └── graph_builder_spec.rb
│   ├── support/
│   │   └── doc_collector.rb                     # Documentation collection helper
│   └── type_guessr/
│       ├── mcp/
│       │   └── standalone_runtime_spec.rb       # MCP standalone runtime tests
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
│           ├── registry/
│           │   ├── method_registry_spec.rb
│           │   ├── signature_registry_spec.rb
│           │   └── variable_registry_spec.rb
│           ├── logger_spec.rb
│           ├── signature_builder_spec.rb
│           ├── type_simplifier_spec.rb
│           └── types_spec.rb
├── docs/
│   ├── adr/                                     # Architecture Decision Records
│   ├── architecture.md                          # Architecture documentation
│   ├── benchmark-report.md                      # Performance benchmark results
│   ├── class.md                                 # Class inference rules (generated)
│   ├── container.md                             # Container inference rules (generated)
│   ├── control.md                               # Control flow rules (generated)
│   ├── literal.md                               # Literal inference rules (generated)
│   └── variable.md                              # Variable inference rules (generated)
├── .rspec                                       # RSpec configuration
├── .rubocop.yml                                 # RuboCop configuration
├── Gemfile
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
- Uses injected MethodRegistry and VariableRegistry for storage

#### 6. Types (`types.rb`)
- Type representations: `ClassInstance`, `ArrayType`, `HashType`, `HashShape`, `Union`, `Unknown`, etc.

#### 7. SignatureRegistry (`registry/signature_registry.rb`)
- Preloads stdlib RBS signatures at startup (~250ms, ~10MB)
- O(1) hash lookup for method return types
- Handles overload resolution and block parameter types

#### 8. MethodRegistry (`registry/method_registry.rb`)
- Stores project method definitions (DefNode)
- Supports inheritance via ancestry_provider
- Provides method lookup and search

#### 9. VariableRegistry (`registry/variable_registry.rb`)
- Stores instance/class variable definitions
- Supports inheritance for instance variable lookup

#### 10. SignatureBuilder (`signature_builder.rb`)
- Generates method signatures from inferred types
- Formats parameter types and return types for display

#### 11. TypeSimplifier (`type_simplifier.rb`)
- Simplifies complex union types
- Normalizes type representations for cleaner display

### MCP Layer (`lib/type_guessr/mcp/`)

#### 1. Server (`server.rb`)
- Standalone MCP server exposing type inference via stdio transport
- Indexes project on startup (RubyIndexer + TypeGuessr)
- Provides tools: `infer_type`, `get_method_signature`, `search_methods`

#### 2. StandaloneRuntime (`standalone_runtime.rb`)
- Mirrors RuntimeAdapter's query interface without ruby-lsp's GlobalState
- Thread-safe inference via mutex
- Methods: `index_parsed_file`, `finalize_index!`, `preload_signatures!`, `infer_at`, `method_signature`, `search_methods`

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

#### 6. GraphBuilder (`graph_builder.rb`)
- Constructs the node dependency graph from source files
- Coordinates with PrismConverter for AST processing

#### 7. TypeInferrer (`type_inferrer.rb`)
- Coordinates type inference across the system
- Bridges Ruby LSP's type inference with TypeGuessr's inference

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

Before proposing architectural changes, **check `docs/adr/` for existing decisions**.
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
