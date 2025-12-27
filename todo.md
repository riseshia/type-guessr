# TypeGuessr TODO

> Based on plan.md (2025-12-12). Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

---

## Testing Infrastructure

### Integration Test Refactoring
- [x] Create `spec/integration/` directory
- [x] Create `spec/integration/hover_spec.rb` for E2E hover tests
- [x] Move LSP server-based tests from `spec/ruby_lsp/hover_spec.rb`
- [x] Add missing scenarios from qa.md:
  - [x] 2.2 Namespaced .new (`Admin::User.new`)
  - [x] 4.2 Local vs Instance variable distinction
  - [x] 7.1 Debug mode explicit test
- [x] Clean up `spec/ruby_lsp/hover_spec.rb` to keep only unit tests

---

## Phase 5: Hover Enhancement

### 5.0 Type System Integration (Pre-requisite) ✅ COMPLETED

Refactor codebase to use Types classes instead of strings:

- [x] VariableIndex: Store types as Types objects instead of strings
- [x] TypeResolver: Return Types objects instead of strings
- [x] TypeMatcher: Return Types objects instead of string arrays
- [x] HoverContentBuilder: Use Types objects + TypeFormatter for output

**Status:** All components now use Types objects consistently throughout the codebase.

---

### 5.1 Method Call Assignment Type Inference

Infer variable types from method call assignments at hover time:
- Example: `hoge2 = hoge.to_s` → hover on `hoge2` shows `String`
- Example: `result = name.upcase.length` → hover on `result` shows `Integer`

**Implementation Steps:**

1. VariableIndex Extension
  - [x] Store call info when assignment value is CallNode
  - [x] New field: `call_info: { receiver_var, method_name }` or similar structure
  - [x] Handle chained calls recursively (e.g., `a.b.c`)

2. ASTAnalyzer Modification
  - [x] In `visit_local_variable_write_node` etc., detect CallNode values
  - [x] Extract and store receiver variable name and method name
  - [x] Support chained calls by storing nested call structure

3. TypeResolver Modification
  - [x] When resolving variable type, check for `call_info`
  - [x] If present: resolve receiver type (recursive) → RBS lookup → return type
  - [x] Use RBSProvider.get_method_return_type for stdlib methods
  - [x] Return Unknown for user-defined methods (no RBS)

**Status:** Implemented with integration tests (hover_spec) passing.

**Context:**
- Type inference happens at hover time, not AST analysis time
- RBSProvider already has `get_method_return_type` method
- User-defined class methods without RBS return Unknown

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
