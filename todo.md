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

#### Phase 5.2b: Method Chain Support (High Risk, 4-6h)

- [ ] Create `MethodChainResolver` class:
  ```ruby
  # lib/ruby_lsp/type_guessr/method_chain_resolver.rb
  class MethodChainResolver
    MAX_DEPTH = 5        # Prevent infinite recursion
    TIMEOUT_MS = 50      # Per-chain timeout

    def resolve_receiver_type(call_node, context:, depth: 0)
      # Recursive resolution with depth limit
    end
  end
  ```
- [ ] Handle receiver types:
  - [ ] Variable nodes → delegate to VariableTypeResolver
  - [ ] CallNode → recurse with depth+1, get return type from RBS
  - [ ] SelfNode → use current class context
- [ ] Integrate into `on_call_node_enter`:
  - [ ] Try chain resolution first
  - [ ] Fallback to variable resolution
- [ ] Add integration tests:
  - [ ] `'str = "hello"; str.chars.first'` → shows `String?`
  - [ ] Depth limit test (6+ levels → nil)

#### Signature Display Features (Future)

- [ ] Display method signatures with overloads (multiple lines)
- [ ] Filter overloads at call-site using:
  - [ ] Positional arg count mismatch
  - [ ] Required keyword missing
  - [ ] Known arg type mismatch (literals, etc.)

---

### 5.3 Definition (def) Hover (Medium Risk, 2-3h)

**Goal:** Show complete method signature (parameters + return type) when hovering on method definitions.

**Approach:** Infer parameter types on-demand at hover time (no indexing needed).

- [ ] Add `:def` to `HOVER_NODE_TYPES`
- [ ] Implement `on_def_node_enter(node)`:
  - [ ] Iterate through parameters and infer types from default values
  - [ ] Use `analyze_value_type` for literals/numbers/.new calls
  - [ ] Use `FlowAnalyzer` to analyze method body for return type
  - [ ] Format complete signature: `(params) -> ReturnType`
  - [ ] Handle all parameter kinds: required, optional, keyword, rest, block
  - [ ] Handle errors gracefully (return nil on failure)
- [ ] Parameter type inference (on-demand):
  - [ ] Required params without default → `untyped`
  - [ ] Optional params with default → infer from default value (literal/number/.new)
  - [ ] Keyword params → similar to optional
  - [ ] Rest/keyword rest → `*untyped`, `**untyped`
  - [ ] Block → `&block`
- [ ] Return type inference:
  - [ ] `return expr` statements
  - [ ] Last expression of method body
  - [ ] Union of multiple return paths
- [ ] Add integration tests:
  - [ ] `'def foo; 42; end'` → shows `() -> Integer`
  - [ ] `'def greet(name, age = 20); ...; end'` → shows `(untyped name, ?Integer age) -> String`
  - [ ] Multiple return paths → shows union type

---

### 5.4 FlowAnalyzer Integration (High Risk, 4-6h)

**Goal:** Use FlowAnalyzer for more accurate variable type inference.

- [ ] Add parallel path in Hover without modifying VariableTypeResolver:
  ```ruby
  def add_hover_content(node)
    # 1. Try FlowAnalyzer (new path)
    flow_type = try_flow_analysis(node)
    if flow_type && flow_type != Types::Unknown.instance
      # Use flow-inferred type
      return
    end

    # 2. Existing path (fallback)
    type_info = @type_resolver.resolve_type(node)
    # ...
  end
  ```
- [ ] Implement `try_flow_analysis(node)`:
  - [ ] Extract containing scope source
  - [ ] Run FlowAnalyzer on scope
  - [ ] Query type at node location
  - [ ] Catch all errors → return nil
- [ ] Scope-limited analysis for performance (<20ms target)

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

## Phase 6: Heuristic Fallback

### 6.1 Method-Call Set Heuristic
- [ ] Use existing method-call set data as fallback for `Unknown` receivers
- [ ] If exactly 1 class matches call-set → `ClassInstance(candidate)`
- [ ] If multiple candidates → union or `Unknown` (with cutoff)

**Context:**
- This is 2nd priority after flow analysis
- Existing `TypeMatcher` logic can be reused/adapted

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
| 1 | 5.3 Def Node Hover | Medium | 2-3h | Pending |
| 2 | 5.2b Call Node Hover (chains) | High | 4-6h | Pending |
| 3 | 5.4 FlowAnalyzer Integration | High | 4-6h | Pending |

**Total Estimated Effort:** 10-15 hours (remaining)

**Recent Change:**
Phase 5.5 has been merged into Phase 5.3. Parameter type inference is performed
on-demand at hover time (fast for literals/numbers/.new), eliminating the need
for separate indexing phase.

**Next Steps:**
1. Implement 5.3 (Def Node Hover) - includes parameter type inference
2. Collect feedback before proceeding to complex phases (5.2b, 5.4)
