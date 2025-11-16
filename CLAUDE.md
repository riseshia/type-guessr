# Ruby LSP Guesser - Project Context

## Project Overview

Ruby LSP Guesser is a Ruby LSP addon that provides **heuristic type inference** without requiring explicit type annotations. The goal is to achieve a "useful enough" development experience by prioritizing practical type hints over perfect accuracy.

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
- **Repository:** https://github.com/riseshia/ruby-lsp-guesser

## Project Structure

```
ruby-lsp-guesser/
├── .claude/
│   └── commands/
│       └── go.md                                # TDD cycle automation command
├── .github/
│   └── workflows/                               # GitHub Actions CI configuration
├── bin/
│   ├── console
│   └── setup
├── lib/
│   ├── ruby-lsp-guesser.rb                      # Main entry point
│   └── ruby_lsp/
│       └── ruby_lsp_guesser/
│           ├── addon.rb                         # LSP addon registration
│           ├── ast_visitor.rb                   # AST traversal for method call tracking
│           ├── hover.rb                         # Hover provider implementation
│           ├── hover_content_builder.rb         # Hover content formatting and debug mode
│           ├── method_signature.rb              # Method signature representation
│           ├── method_signature_index.rb        # Index of method signatures from RBS
│           ├── parameter.rb                     # Method parameter representation
│           ├── rbs_signature_indexer.rb         # RBS file parser and indexer
│           ├── ruby_index_adapter.rb            # Adapter for RubyIndexer access
│           ├── scope_resolver.rb                # Scope type and ID resolution
│           ├── type_matcher.rb                  # Type matching logic
│           ├── variable_index.rb                # Variable type information storage
│           ├── variable_type_resolver.rb        # Variable type inference logic
│           └── version.rb                       # Version constant
├── test/
│   ├── test_helper.rb
│   └── ruby_lsp/
│       ├── test_ast_visitor.rb
│       ├── test_guesser.rb
│       ├── test_hover.rb
│       ├── test_method_signature.rb
│       ├── test_method_signature_index.rb
│       ├── test_parameter.rb
│       ├── test_rbs_signature_indexer.rb
│       ├── test_scope_resolver.rb
│       ├── test_type_matcher.rb
│       └── test_variable_index.rb
├── .rubocop.yml                                 # RuboCop configuration
├── CLAUDE.md                                    # Project context for Claude
├── Gemfile
├── Rakefile                                     # Rake tasks (test, rubocop)
├── README.md
└── ruby-lsp-guesser.gemspec                     # Gem specification
```

## Core Components

### 1. Addon (lib/ruby_lsp/ruby_lsp_guesser/addon.rb)
- Registers the addon with Ruby LSP
- Implements the Ruby LSP addon interface
- Creates hover listeners via `create_hover_listener`
- Initializes RBS signature indexing on activation

### 2. Hover (lib/ruby_lsp/ruby_lsp_guesser/hover.rb)
- **Purpose:** Provides type information on hover
- Listens to AST node events for variables and constants
- Delegates type resolution to VariableTypeResolver
- Delegates content formatting to HoverContentBuilder
- Returns formatted hover content with type information

### 3. Hover Content Builder (lib/ruby_lsp/ruby_lsp_guesser/hover_content_builder.rb)
- **Purpose:** Formats hover content from type information
- Handles debug mode configuration (ENV variable or config file)
- Formats inferred types, ambiguous types, and debug content
- Separates presentation logic from type inference logic

### 4. Variable Type Resolver (lib/ruby_lsp/ruby_lsp_guesser/variable_type_resolver.rb)
- **Purpose:** Resolves variable types by analyzing definitions and method calls
- Extracts variable names from various node types (local, instance, class variables, parameters)
- Retrieves direct types from literal assignments or `.new` calls
- Collects method calls for variables using VariableIndex
- Integrates with TypeMatcher for method-based type inference

### 5. AST Visitor (lib/ruby_lsp/ruby_lsp_guesser/ast_visitor.rb)
- **Purpose:** Traverses AST to collect method call patterns
- Inherits from Prism::Visitor
- Tracks method calls on variables throughout the document
- Feeds data to VariableIndex for type inference

### 6. RBS Signature Indexer (lib/ruby_lsp/ruby_lsp_guesser/rbs_signature_indexer.rb)
- **Purpose:** Parses and indexes RBS type definitions
- Searches for RBS files in project and gem dependencies
- Extracts method signatures from RBS definitions
- Populates MethodSignatureIndex with type information

### 7. Method Signature Index (lib/ruby_lsp/ruby_lsp_guesser/method_signature_index.rb)
- **Purpose:** Central storage for method signatures
- Maps class names to their method signatures
- Enables reverse lookup: method name → possible classes
- Used for method-based type inference

### 8. Variable Index (lib/ruby_lsp/ruby_lsp_guesser/variable_index.rb)
- **Purpose:** Stores inferred types for variables
- Tracks variable assignments and method calls
- Stores type information from literal assignments and `.new` calls
- Provides public API for querying variable types and method calls
- Encapsulates internal data structures for better maintainability

### 9. Type Matcher (lib/ruby_lsp/ruby_lsp_guesser/type_matcher.rb)
- **Purpose:** Matches method calls to type signatures
- Compares observed method calls with Ruby LSP's index
- Determines compatible types based on available methods
- Core of the heuristic type inference logic

### 10. Ruby Index Adapter (lib/ruby_lsp/ruby_lsp_guesser/ruby_index_adapter.rb)
- **Purpose:** Adapter for accessing RubyIndexer internals
- Provides stable interface isolating TypeMatcher from implementation details
- Encapsulates access to Ruby LSP's index entries
- Retrieves class/module entries and resolves methods

### 11. Scope Resolver (lib/ruby_lsp/ruby_lsp_guesser/scope_resolver.rb)
- **Purpose:** Provides common scope resolution logic
- Determines scope type based on variable name (local/instance/class)
- Generates scope IDs for different contexts (class, method, top-level)
- Shared utility module used by both ASTVisitor and VariableTypeResolver

### 12. Method Signature (lib/ruby_lsp/ruby_lsp_guesser/method_signature.rb)
- **Purpose:** Represents a method's type signature
- Stores method name, parameters, and return type
- Extracted from RBS definitions

### 13. Parameter (lib/ruby_lsp/ruby_lsp_guesser/parameter.rb)
- **Purpose:** Represents a method parameter
- Stores parameter name, type, and metadata (required/optional, keyword/positional)
- Used in method signature matching

## Development Workflow

### Setup
```bash
bin/setup
```

### Running Tests
```bash
rake test
# or
bundle exec rake test
```

### Running Linter
```bash
rake rubocop
# or
bundle exec rubocop
```

### Running All Checks (Default)
```bash
rake
# Runs both tests and rubocop
```

### Installing Locally
```bash
bundle exec rake install
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

### Automatic TDD Mode with `/go` Command

**CRITICAL:** When implementing features or fixing bugs:

1. **ALWAYS use `/go` command first** - Do not implement directly
2. The `/go` command will automatically:
   - Find the next unmarked test in `plan.md`
   - Mark it as [~] (in progress)
   - Write the test first (Red phase)
   - Implement minimal code to pass (Green phase)
   - Refactor if needed
   - Mark it as [x] (completed)
   - Commit with clear message

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

4. **Testing:** Uses Minitest for testing

5. **Naming:**
   - Module: `RubyLsp::Guesser`
   - Gem: `ruby-lsp-guesser`
   - Files follow Ruby conventions (snake_case)

## Before Making Changes

**Pre-Implementation Checklist:**

1. **Check for `/go` command** - If implementing features/fixes, use `/go` instead of direct implementation
2. **Read relevant files in parallel** - Use multiple Read tool calls together
3. **Always run tests first:**
   ```bash
   rake test
   ```
4. **Check RuboCop:**
   ```bash
   rake rubocop
   ```
5. **Run all checks:**
   ```bash
   rake
   ```

**Pre-Commit Checklist:**

1. **Run linter on changed files FIRST** - Fix violations before committing
   ```bash
   bin/rubocop <changed_files>
   ```
2. **Run all tests** - Ensure nothing breaks
   ```bash
   rake test
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
1. After editing any Ruby file, run: `bin/rubocop <file_path>`
2. If violations found, fix them immediately
3. Commit once with all changes together (code + linting fixes)

**Never create separate "Fix rubocop" commits** - always fix linting issues in the same commit as the code change.

## Common Tasks

### Adding a New Hover Feature
1. Edit `lib/ruby_lsp/ruby_lsp_guesser/hover.rb`
2. Add new node listener methods if needed
3. Register new listeners in `register_listeners`
4. Add tests in `test/ruby_lsp/test_hover.rb`
5. Run `rake test` to verify

### Updating Dependencies
1. Edit `ruby-lsp-guesser.gemspec`
2. Run `bundle install`
3. Test thoroughly with `rake test`

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

- **TDD is mandatory:** Use `/go` command for implementations, follow Red-Green-Refactor cycle
- **Linter-first:** Run `bin/rubocop` on changed files BEFORE committing
- **Atomic commits:** Group related changes (code + tests + linting) into single commits
- **Test-driven:** Run `rake test` before and after making changes
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
