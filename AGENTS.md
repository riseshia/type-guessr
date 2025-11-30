# TypeGuessr - Project Context

## Project Overview

TypeGuessr is a Ruby LSP addon that provides **heuristic type inference** without requiring explicit type annotations. The goal is to achieve a "useful enough" development experience by prioritizing practical type hints over perfect accuracy.

**Core Approach:**
- Infers types from **method call patterns** (inspired by duck typing)
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
│   └── setup
├── lib/
│   ├── type-guessr.rb                           # Main entry point
│   ├── ruby_lsp/
│   │   └── type_guessr/
│   │       ├── addon.rb                         # LSP addon registration
│   │       ├── hover.rb                         # Hover provider implementation
│   │       ├── hover_content_builder.rb         # Hover content formatting
│   │       ├── type_matcher.rb                  # Type matching (LSP integration wrapper)
│   │       └── variable_type_resolver.rb        # Variable type inference logic
│   └── type_guessr/
│       ├── version.rb                           # Version constant
│       ├── core/
│       │   ├── ast_analyzer.rb                  # AST traversal for method call tracking
│       │   ├── scope_resolver.rb                # Scope type and ID resolution
│       │   ├── type_matcher.rb                  # Core type matching logic
│       │   ├── type_resolver.rb                 # Type resolution logic
│       │   └── variable_index.rb                # Variable type information storage
│       └── integrations/
│           └── ruby_lsp/
│               ├── hover_content_builder.rb     # LSP-specific hover formatting
│               └── index_adapter.rb             # Adapter for RubyIndexer access
├── spec/
│   ├── spec_helper.rb
│   ├── ruby_lsp/
│   │   ├── addon_loading_spec.rb
│   │   ├── ast_visitor_spec.rb
│   │   ├── guesser_spec.rb
│   │   ├── hover_spec.rb
│   │   ├── independent_addon_loading_spec.rb
│   │   ├── scope_resolver_spec.rb
│   │   ├── type_matcher_spec.rb
│   │   └── variable_index_spec.rb
│   └── type_guessr/
│       └── core/
│           └── type_inferrer_spec.rb
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
- **Integrations (`lib/ruby_lsp/type_guessr/`)**: Ruby LSP-specific adapter layer

### Core Layer (`lib/type_guessr/core/`)

#### 1. AST Analyzer (`ast_analyzer.rb`)
- **Purpose:** Traverses AST to collect method call patterns
- Inherits from `Prism::Visitor`
- Tracks method calls on variables throughout the document
- Feeds data to VariableIndex for type inference
- **Aliased as:** `RubyLsp::TypeGuessr::ASTVisitor`

#### 2. Scope Resolver (`scope_resolver.rb`)
- **Purpose:** Provides common scope resolution logic
- Determines scope type based on variable name (local/instance/class)
- Generates scope IDs for different contexts (class, method, top-level)
- Shared utility module used by ASTAnalyzer and VariableTypeResolver

#### 3. Variable Index (`variable_index.rb`)
- **Purpose:** Stores guessed types for variables
- Tracks variable assignments and method calls
- Stores type information from literal assignments and `.new` calls
- Provides public API for querying variable types and method calls

#### 4. Type Matcher (`type_matcher.rb`)
- **Purpose:** Core type matching logic
- Compares observed method calls with known type signatures
- Determines compatible types based on available methods
- Framework-agnostic implementation

#### 5. Type Resolver (`type_resolver.rb`)
- **Purpose:** High-level type resolution coordination
- Orchestrates AST analysis and type matching
- Provides unified interface for type queries

### Integration Layer (`lib/ruby_lsp/type_guessr/`)

#### 6. Addon (`addon.rb`)
- Registers the addon with Ruby LSP
- Implements the Ruby LSP addon interface
- Creates hover listeners via `create_hover_listener`
- Starts background AST traversal on activation

#### 7. Hover (`hover.rb`)
- **Purpose:** Provides type information on hover
- Uses metaprogramming to dynamically create listener methods for supported node types
- Defines supported node types in HOVER_NODE_TYPES constant
- Delegates type resolution to VariableTypeResolver
- Delegates content formatting to HoverContentBuilder

#### 8. Hover Content Builder (`hover_content_builder.rb`)
- **Purpose:** Formats hover content from type information
- Handles debug mode configuration (ENV variable or config file)
- Formats guessed types, ambiguous types, and debug content

#### 9. Variable Type Resolver (`variable_type_resolver.rb`)
- **Purpose:** Resolves variable types by analyzing definitions and method calls
- Extracts variable names from various node types
- Retrieves direct types from literal assignments or `.new` calls
- Integrates with TypeMatcher for method-based type inference

#### 10. Type Matcher (`type_matcher.rb`)
- **Purpose:** Ruby LSP-specific type matching wrapper
- Integrates core TypeMatcher with Ruby LSP's index
- Uses IndexAdapter for accessing RubyIndexer

#### 11. Index Adapter (`integrations/ruby_lsp/index_adapter.rb`)
- **Purpose:** Adapter for accessing RubyIndexer using public APIs
- Provides stable interface isolating from Ruby LSP implementation details
- Uses only public APIs for better compatibility with ruby-lsp updates

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
bundle exec rubocop
```

### Running All Checks
```bash
bundle exec rspec && bundle exec rubocop
```

### Console
```bash
bin/console
```

## TDD Development Workflow

This project follows strict Test-Driven Development (TDD) practices based on Kent Beck's principles.

### TDD Cycle: Red → Green → Refactor

1. **Red:** Write a failing test first
2. **Green:** Write minimal code to make the test pass
3. **Refactor:** Clean up code while keeping tests green
4. **Commit:** Only commit when all tests pass

### Code Quality Standards

- Eliminate duplication ruthlessly
- Express intent clearly through naming
- Keep methods small and focused
- Use the simplest solution that works
- Separate structural changes from behavioral changes

## Important Conventions

1. **Language:** **ALL code-related content MUST be written in English:**
   - Commit messages (both title and body)
   - Pull request titles and descriptions
   - Code comments
   - Variable names, function names, class names
   - Documentation and README updates
   - Test descriptions
   - Error messages and log output
   - **Exception:** You may communicate with the user in Korean for clarifications and discussions, but all artifacts (commits, PRs, code) must be in English

2. **Frozen String Literals:** All Ruby files use `# frozen_string_literal: true`

3. **Code Style:** Follows RuboCop rules defined in `.rubocop.yml`

4. **Testing:** Uses RSpec for testing

5. **Naming:**
   - Module: `TypeGuessr` (core), `RubyLsp::TypeGuessr` (LSP integration)
   - Gem: `type-guessr`
   - Files follow Ruby conventions (snake_case)

## Before Making Changes

**Pre-Implementation Checklist:**

1. **Read relevant files in parallel** - Use multiple Read tool calls together
2. **Always run tests first:**
   ```bash
   bundle exec rspec
   ```
3. **Check RuboCop:**
   ```bash
   bundle exec rubocop
   ```

**Pre-Commit Checklist:**

1. **Run linter on changed files FIRST** - Fix violations before committing
   ```bash
   bundle exec rubocop <changed_files>
   ```
2. **Run all tests** - Ensure nothing breaks
   ```bash
   bundle exec rspec
   ```
3. **Check for untracked files** - Add relevant new files
   ```bash
   git status
   ```
4. **Make ONE atomic commit** - Group all related changes together (code + linting + new files)

## Commit Strategy

### Atomic Commits

**Always group related changes into single commits:**

✅ **Good** - Single commit:
```
"Add method call tracking for type inference"
- Implement AST traversal
- Add logging for method calls
- Fix RuboCop violations
- Add test cases
```

❌ **Bad** - Multiple commits:
```
"Add method call tracking"
"Fix rubocop violations"
"Add tests"
```

### Linter-First Strategy

**CRITICAL:** Run linter BEFORE committing to avoid separate "fix linting" commits.

**Workflow:**
1. After editing any Ruby file, run: `bundle exec rubocop <file_path>`
2. If violations found, fix them immediately
3. Commit once with all changes together (code + linting fixes)

**Never create separate "Fix rubocop" commits** - always fix linting issues in the same commit as the code change.

## Common Tasks

### Adding a New Hover Feature
1. Edit `lib/ruby_lsp/type_guessr/hover.rb`
2. Add new node listener methods if needed
3. Register new listeners in `register_listeners`
4. Add tests in `spec/ruby_lsp/hover_spec.rb`
5. Run `bundle exec rspec` to verify

### Updating Dependencies
1. Edit `type-guessr.gemspec`
2. Run `bundle install`
3. Test thoroughly with `bundle exec rspec`

### Fixing Linting Issues
```bash
# Auto-fix safe issues
bundle exec rubocop -a

# Auto-fix all issues (use with caution)
bundle exec rubocop -A
```

## Type Inference Strategy

### Method Call Pattern Collection

The hover provider collects method call patterns by outputting to STDERR:
- Variable name being analyzed
- List of method calls on that variable
- Location information for each call

### Heuristic Type Inference (Planned)

This collected data enables type guessing through:

1. **Method name uniqueness analysis:**
   - If `recipe.comments` is found and `comments` method exists only in `Recipe` class → infer `recipe` type as `Recipe`
   - Works best in large applications where method names tend to be unique

2. **Variable naming conventions:**
   - Plural names (`users`, `items`) → likely Array
   - Suffixes like `_id`, `_count`, `_num` → likely Integer
   - Suffixes like `_name`, `_title` → likely String

3. **RBS integration:**
   - Use RBS definitions as base type information
   - Fill gaps with heuristic inference

## Testing Strategy

- Unit tests for each component
- Test files mirror the structure of `lib/`
- Use Minitest assertions
- Mock/stub LSP interfaces as needed

## Notes for Claude

### Project Understanding

- **Project Goal:** This is NOT just a hover provider - it's a **heuristic type inference system** that collects method call patterns to guess types without explicit annotations
- **Core Philosophy:** Pragmatic type hints over perfect accuracy
- **Type inference focus:** When adding features, consider how they contribute to collecting data for type guessing

### Development Process

- **TDD is mandatory:** Follow Red-Green-Refactor cycle
- **Linter-first:** Run `bundle exec rubocop` on changed files BEFORE committing
- **Atomic commits:** Group related changes (code + tests + linting) into single commits
- **Test-driven:** Run `bundle exec rspec` before and after making changes
- **AST traversal:** When working with Prism nodes, be careful with node types and methods

### TodoWrite Usage

**Skip TodoWrite for simple tasks** (single file, 1-2 steps, simple fixes)

**Use TodoWrite only for complex tasks:**
- 3+ distinct files need changes
- Multiple independent systems affected
- User explicitly lists multiple tasks
- Complex multi-step requiring research + design + implementation

**Rule:** Can you complete in one focused session without tracking? → No TodoWrite

### Parallel Execution

**ALWAYS execute operations in parallel when there are no dependencies:**

✅ **Must parallelize:**
- Reading multiple files: `Read(file1.rb) + Read(file2.rb)` together
- Git inspection: `git status + git diff + git log` together
- Independent searches: `Glob + Grep` together

❌ **Only sequential when TRUE dependencies exist:**
- Edit needs Read first (tool requirement)
- Push needs commit first (data dependency)
- Commit needs tests to pass first
