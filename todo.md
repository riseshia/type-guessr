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

### Implemented Components

| Component | Role | Status |
|-----------|------|--------|
| `Types` | Type representation (Unknown, Union, etc.) | ✅ Complete |
| `TypeDB` | (file, range) → Type storage | ✅ Complete |
| `FlowAnalyzer` | Flow-sensitive local variable analysis | ✅ Complete |
| `RBSProvider` | RBS signature lookup | ✅ Complete (not integrated) |
| `TypeFormatter` | Type → RBS-style string | ✅ Complete |

### 5.0 Type System Integration ✅ COMPLETED

Refactor codebase to use Types classes instead of strings:

- [x] VariableIndex: Store types as Types objects instead of strings
- [x] TypeResolver: Return Types objects instead of strings
- [x] TypeMatcher: Return Types objects instead of string arrays
- [x] HoverContentBuilder: Use Types objects + TypeFormatter for output

---

### 5.1 Method Call Assignment Type Inference ✅ COMPLETED

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

---

### 5.2 Call Node Hover (Method Signature)

**Goal:** Show RBS method signatures when hovering on method calls.

**Scope:** Two-phase implementation (basic → chain support)

#### Phase 5.2a: Variable Receivers Only ✅ COMPLETED

- [x] Add `:call` to `HOVER_NODE_TYPES` in `hover.rb`
- [x] Implement `on_call_node_enter(node)`:
  - [x] Check if receiver is variable node (Local/Instance/ClassVariableReadNode)
  - [x] Resolve receiver type using existing `VariableTypeResolver`
  - [x] Query `RBSProvider.get_method_signatures(receiver_type, method_name)`
  - [x] Format and display signatures
- [x] Add helper `variable_receiver?(node)` method
- [x] Add integration tests:
  - [x] `'str = "hello"; str.upcase'` → shows method signatures
  - [x] Unknown receiver → returns nil gracefully
  - [x] Instance variable receiver (`@name.downcase`)

**Status:** Implemented in hover.rb:62-83. All 211 tests passing (208 existing + 3 new).

#### Phase 5.2b: Method Chain Support ✅ COMPLETED

**Implementation:** Recursive type resolution integrated into Hover class (not separate class for simplicity)

- [x] Implement `resolve_receiver_type_recursively` in Hover class with MAX_DEPTH = 5
- [x] Handle receiver types:
  - [x] Variable nodes → delegate to existing VariableTypeResolver
  - [x] CallNode → recurse with depth+1, get return type from RBS
  - [x] Literal nodes → Array, Hash, String, Integer, Float, Symbol, etc.
- [x] Integrate into `on_call_node_enter`:
  - [x] Replace variable-only check with recursive chain resolution
  - [x] Query RBS for return types at each chain level
- [x] Add integration tests:
  - [x] `'str.chars.first'` → shows Array signatures
  - [x] `'arr.map { }.first'` → shows Array signatures
  - [x] `'arr.select { }.map { }.compact'` → shows Array signatures
  - [x] Depth limit test (7 levels → nil)

**Status:** Implemented in hover.rb:128-190. All 4 integration tests passing (216 total tests passing).

#### Signature Display Features (Future)

- [ ] Display method signatures with overloads (multiple lines)
- [ ] Filter overloads at call-site using:
  - [ ] Positional arg count mismatch
  - [ ] Required keyword missing
  - [ ] Known arg type mismatch (literals, etc.)

---

### 5.3 Definition (def) Hover ✅ COMPLETED

**Goal:** Show complete method signature (parameters + return type) when hovering on method definitions.

**Approach:** Infer parameter types on-demand at hover time (no indexing needed).

- [x] Add `:def` to `HOVER_NODE_TYPES`
- [x] Add `Prism::DefNode` and `Prism::CallNode` to `HOVER_TARGET_NODES` in addon
- [x] Implement `on_def_node_enter(node)`:
  - [x] Iterate through parameters and infer types from default values
  - [x] Use `analyze_value_type` for literals/numbers/.new calls
  - [x] Use `FlowAnalyzer` to analyze method body for return type
  - [x] Format complete signature: `(params) -> ReturnType`
  - [x] Handle all parameter kinds: required, optional, keyword, rest, block
  - [x] Handle errors gracefully (return nil on failure)
- [x] Parameter type inference (on-demand):
  - [x] Required params without default → `untyped`
  - [x] Optional params with default → infer from default value (literal/number/.new)
  - [x] Keyword params → similar to optional
  - [x] Rest/keyword rest → `*args`, `**kwargs`
  - [x] Block → `&block`
- [x] Return type inference:
  - [x] `return expr` statements
  - [x] Last expression of method body
  - [x] Union of multiple return paths
  - [x] Enhanced FlowAnalyzer to support `InterpolatedStringNode` and `IfNode`
- [x] Add integration tests:
  - [x] `'def foo; 42; end'` → shows `() -> Integer`
  - [x] `'def greet(name, age = 20); ...; end'` → shows `(untyped name, ?Integer age) -> String`
  - [x] Multiple return paths → shows union type
  - [x] Keyword parameters → shows correct signature

**Status:** Implemented in hover.rb:87-328, flow_analyzer.rb:192-249, addon.rb:39-40. All 4 integration tests passing (212 total tests passing).

---

### 5.4 FlowAnalyzer Integration ✅ COMPLETED

**Goal:** Use FlowAnalyzer for more accurate variable type inference.

- [x] Add parallel path in Hover without modifying VariableTypeResolver
- [x] Implement `try_flow_analysis(node)`:
  - [x] Extract containing scope source using document parsing
  - [x] Run FlowAnalyzer on method scope
  - [x] Query type at node location with variable name
  - [x] Catch all errors → return nil and fall back
- [x] Implement `find_containing_method` using DefNodeFinder visitor
- [x] Fix FlowAnalyzer to preserve branch-local types
- [x] Add `merge_branch_envs` for proper branch type merging
- [x] Update `type_at` to accept variable name parameter

**Status:** Implemented in hover.rb:383-484, flow_analyzer.rb:28-360. All 4 integration tests passing (224 total tests passing).

---

### ~~5.5 Parameter Default Value Type Inference~~ ✅ MERGED INTO 5.3

**Status:** This phase has been merged into Phase 5.3.

**Rationale:** Parameter type inference is simple and fast (literals/numbers/.new).
It's more efficient to infer on-demand at hover time rather than storing in index.

See Phase 5.3 for the integrated implementation approach.

---

### 5.6 TypeFormatter Integration ✅ COMPLETED

**Goal:** Unified output formatting for all type displays.

- [x] Update `HoverContentBuilder` to use TypeFormatter:
  ```ruby
  formatted = type_name.is_a?(String) ? type_name : TypeFormatter.format(type_name)
  "**Guessed type:** `#{formatted}`"
  ```
- [x] Ensure consistent formatting across all hover scenarios

**Status:** Already completed during Phase 5.0. All type formatting in `HoverContentBuilder` consistently uses `TypeFormatter.format()` (lines 99, 144, 166, 188). 26 integration tests passing.

---

## Phase 6: Heuristic Fallback ✅ COMPLETED

### 6.1 Method-Call Set Heuristic ✅ COMPLETED
- [x] Use existing method-call set data as fallback for `Unknown` receivers
- [x] If exactly 1 class matches call-set → `ClassInstance(candidate)`
- [x] If multiple candidates → `Union` of matching types
- [x] Integrate into `resolve_call_chain` for unknown receivers
- [x] Update `HoverContentBuilder` to prefer matching_types over Unknown direct_type

**Status:** Implemented in hover.rb:389-423, hover_content_builder.rb:43. 222 tests passing (1 pending).

---

## Performance Considerations

### Response Time Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Hover response | < 100ms | Total response time |
| RBS first load | ~500ms | One-time, lazy loaded |
| RBS lookup | < 10ms | After initial load |
| FlowAnalyzer | < 20ms | Scope-limited |
| Chain resolution | < 50ms | New, needs benchmarking |

### Timeout Configuration

```ruby
module TypeGuessr::Config
  HOVER_TIMEOUT_MS = 100
  CHAIN_TIMEOUT_MS = 50
  FLOW_ANALYSIS_TIMEOUT_MS = 20
end
```

---

## Error Handling Strategy

### Fallback Chain

```
FlowAnalyzer error
      ↓
MethodChainResolver
      ↓
VariableTypeResolver (existing)
      ↓
TypeMatcher (existing)
      ↓
Return Unknown / nil
```

### Rules

1. **Never crash on hover** - All exceptions caught and logged
2. **Graceful degradation** - Fall back to existing system on any failure
3. **Timeout handling** - Return nil on timeout, don't block LSP
4. **RBS unavailable** - Continue with heuristic inference only

---

## Future Work (Post-MVP)

### Caching & Performance
- [ ] Add TypeDB caching with AST node location as key
- [ ] Add `MethodSummary` cache (`MethodRef → MethodSummary`)
- [ ] Consider scope-level summary caching

### Extended Inference
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

---

## Implementation Priority Summary

| Order | Task | Risk | Time | Status |
|-------|------|------|------|--------|
| - | 5.0 Type System Integration | - | - | ✅ Done |
| - | 5.1 Method Call Assignment | - | - | ✅ Done |
| - | 5.6 TypeFormatter Integration | Low | 1h | ✅ Done |
| - | 5.2a Call Node Hover (basic) | Medium | 2-3h | ✅ Done |
| - | ~~5.5 Parameter Default Types~~ | - | - | ✅ Merged into 5.3 |
| - | 5.3 Def Node Hover | Medium | 2-3h | ✅ Done |
| - | 5.2b Call Node Hover (chains) | High | 4-6h | ✅ Done |
| - | 5.4 FlowAnalyzer Integration | High | 4-6h | ✅ Done |

**Phase 5 (MVP Hover Enhancement): COMPLETED** ✅
**Phase 6 (Heuristic Fallback): COMPLETED** ✅

**Recent Changes:**
- Phase 6 completed with method-call set heuristic for unknown receivers
- Fallback chain: FlowAnalyzer → Direct type → Method chain → Heuristic → Unknown
- All 222 tests passing (1 pending, non-critical edge case)

**Next Steps:**
1. Performance optimization (caching, timeouts, benchmarking)
2. Extended inference (operations, parameter usage patterns)
3. Collect user feedback on implemented features
