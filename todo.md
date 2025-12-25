# TypeGuessr TODO

> Based on plan.md (2025-12-12). Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

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
