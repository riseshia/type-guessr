# TypeGuessr TODO

> Based on plan.md (2025-12-12). Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

---

## Pre-Phase 5: Refactoring

> Refactoring items to address before Phase 5 integration.

### High Priority (Affects Phase 5)

- [ ] Extract variable node types to shared constant
  - Files: `variable_type_resolver.rb`, `type_inferrer.rb`
  - Issue: Same Prism node type list duplicated in both files
  - Solution: Create shared `VARIABLE_NODE_TYPES` constant

- [ ] Extract best-match selection logic in TypeResolver
  - File: `type_resolver.rb` (lines 76-78, 136-138)
  - Issue: Identical `.select.max_by` pattern in two methods
  - Solution: Create `find_best_definition_before(definitions, hover_line)` helper

- [ ] Refactor VariableIndex nested hash iteration
  - File: `variable_index.rb` (multiple methods)
  - Issue: 4-level deep iteration repeated in `size`, `clear_file`, `stats`
  - Solution: Create iterator helper method

### Medium Priority (Maintainability)

- [ ] Consolidate TypeMatcher entry handling patterns
  - File: `type_matcher.rb`
  - Issue: Inconsistent patterns (`any?`, `first`, `find`) for same purpose
  - Solution: Create `find_class_entry`, `is_class?` helpers

- [ ] Unify hash initialization in VariableIndex
  - File: `variable_index.rb` (lines 44-48, 128-132)
  - Issue: Same `||=` chain duplicated for `@index` and `@types`
  - Solution: Create `ensure_nested_hash(root, *keys)` helper

- [ ] Simplify HoverContentBuilder conditional logic
  - File: `hover_content_builder.rb` (lines 19-42)
  - Issue: Debug mode handling repeated 3 times, complex conditionals
  - Solution: Extract `append_debug_info` helper

### Low Priority (Code Style)

- [ ] Consolidate formatting patterns
  - Files: `hover_content_builder.rb`, `type_formatter.rb`
  - Issue: `.map { |t| backticks }.join(", ")` pattern repeated
  - Solution: Create `format_inline_list` helper

---

## Phase 5: Hover Enhancement

### 5.1 Expression Type Hover
- [ ] Update Hover to use TypeDB for variable/expression types
- [ ] Display types in RBS-ish format:
  - [ ] `Unknown` → `untyped`
  - [ ] `Union` → `A | B`
  - [ ] `Array[T]` as-is
  - [ ] `HashShape` → `{ id: Integer, name: String }`

### 5.2 Call Node Hover (Method Signature)
- [ ] Support hover on call expressions (`receiver.method(...)`)
- [ ] Support hover on method name token within call
- [ ] Display method signatures with overloads (multiple lines)
- [ ] Filter overloads at call-site using:
  - [ ] Positional arg count mismatch
  - [ ] Required keyword missing
  - [ ] Known arg type mismatch (literals, etc.)

### 5.3 Definition (def) Hover
- [ ] Show method signature from AST structure
- [ ] Infer return type from:
  - [ ] `return expr` statements
  - [ ] Last expression of method body
  - [ ] Union of multiple return paths
- [ ] Type slots default to `Unknown` when not inferable

**Context:**
- MVP receiver type inference: literals, simple local assignment only
- Unknown receiver → show `Unknown` signature, don't expand globally

---

## Phase 6: Heuristic Fallback

### 6.1 Method-Call Set Heuristic
- [ ] Use existing method-call set data as fallback for `Unknown` receivers
- [ ] If exactly 1 class matches call-set → `ClassInstance(candidate)`
- [ ] If multiple candidates → union or `Unknown` (with cutoff)

**Context:**
- This is 2nd priority after flow analysis
- Existing `TypeMatcher` logic can be reused/adapted

---

## Future Work (Post-MVP)

### Caching & Performance
- [ ] Add TypeDB caching with AST node location as key
- [ ] Add `MethodSummary` cache (`MethodRef → MethodSummary`)
- [ ] Consider scope-level summary caching

### Extended Inference
- [ ] Method call result type (`x.to_i` → `Integer`)
- [ ] Operations (`+`, `*`, etc.) type inference
- [ ] Flow-sensitive refinement through branches/loops
- [ ] Parameter type inference from usage patterns

### Inverted Index
- [ ] Build method name → owner type candidates index
- [ ] Optimize heuristic lookup performance

### UX Improvements
- [ ] Fold/summarize excessive overloads in hover
- [ ] Block type notation (`{ (args) -> ret }`)
- [ ] Project RBS loading from `sig/` folder

---

## Standalone API (Low Priority)

### Create Main TypeGuessr API
- [ ] Add `TypeGuessr.analyze_file(file_path)` method
- [ ] Add `TypeGuessr::Project` class for caching indexes
- [ ] Add `TypeGuessr::Core::FileAnalyzer` for single-file workflow

**Context:**
- Goal: Make core library usable independently from Ruby LSP
- Enables CLI tools, Rails integration, etc.
- Blocked by: Core type model and TypeDB completion
