# TypeGuessr TODO

> Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

**Current Status:**
- ✅ Phase 5 (MVP Hover Enhancement): COMPLETED
- ✅ Phase 6 (Heuristic Fallback): COMPLETED
- 🔄 Phase 7 (Code Quality & Refactoring): IN PROGRESS
- All 222 tests passing (1 pending, non-critical edge case)

---

## Phase 7: Code Quality & Refactoring (Current Priority)

### 7.1 Split hover.rb (High Priority)

**Problem:** `hover.rb` is 529 lines with multiple responsibilities mixed together.

**Current Responsibilities:**
- Variable hover handling (local, instance, class variables)
- Call node hover (method signatures)
- Def node hover (method definition signatures)
- Literal type inference
- Method chain resolution
- FlowAnalyzer integration
- DefNodeFinder nested class

**Proposed Split:**
- [ ] Extract `DefNodeFinder` to `lib/type_guessr/core/def_node_finder.rb`
- [ ] Extract literal type inference to `lib/type_guessr/core/literal_type_analyzer.rb`
- [ ] Consider extracting call chain resolution to dedicated class
- [ ] Keep Hover as thin coordinator that delegates to specialized handlers

### 7.2 Eliminate Duplicate Literal Type Inference (High Priority)

**Problem:** Three nearly identical case statements for literal type inference:

| Location | Method |
|----------|--------|
| `hover.rb:150-176` | `resolve_receiver_type_recursively` |
| `hover.rb:274-301` | `analyze_value_type_for_param` |
| `flow_analyzer.rb:210-233` | `infer_type_from_node` |

**Solution:**
- [ ] Create `LiteralTypeAnalyzer.infer(node)` in core layer
- [ ] Replace all three call sites with single method
- [ ] Ensure consistent behavior across all contexts

### 7.3 Cache RBSProvider Instance (Medium Priority)

**Problem:** `::TypeGuessr::Core::RBSProvider.new` instantiated multiple times per hover request (lines 74, 195).

**Solution:**
- [ ] Cache as `@rbs_provider` instance variable in Hover
- [ ] Lazy initialization on first access

### 7.4 Reduce Verbose Type References (Medium Priority)

**Problem:** Fully qualified type names repeated throughout codebase:
- `::TypeGuessr::Core::Types::Unknown.instance` (13+ occurrences)
- `::TypeGuessr::Core::Types::ClassInstance.new("...")` (20+ occurrences)

**Solutions:**
- [ ] Use `include TypeGuessr::Core::Types` where appropriate
- [ ] Create short aliases: `UNKNOWN = Types::Unknown.instance`
- [ ] Consider `Types.class_instance("String")` factory method

### 7.5 Extract Magic Numbers to Constants (Low Priority)

**Problem:** Magic numbers scattered in code:
- `depth > 5` for max chain depth (hover.rb:148)
- Timeout values referenced in comments but not enforced

**Solution:**
- [ ] Add to Config module:
  ```ruby
  module TypeGuessr::Config
    MAX_CHAIN_DEPTH = 5
    HOVER_TIMEOUT_MS = 100
    CHAIN_TIMEOUT_MS = 50
    FLOW_ANALYSIS_TIMEOUT_MS = 20
  end
  ```

### 7.6 Replace `__send__` Protected Method Access (Low Priority)

**Problem:** `node.location.__send__(:source)` (hover.rb:464) accesses protected method - fragile.

**Solution:**
- [ ] Investigate if Prism provides public API for accessing source
- [ ] If not, document why this workaround is necessary
- [ ] Consider caching source at initialization if possible

### 7.7 Refactor Similar FlowVisitor Methods (Low Priority)

**Problem:** `visit_local_variable_or_write_node` and `visit_local_variable_and_write_node` in flow_analyzer.rb are nearly identical (lines 129-161).

**Solution:**
- [ ] Extract common logic to private helper method
- [ ] Keep operator-specific semantics in visitor methods

---

## Performance Optimization (Future)

### Response Time Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Hover response | < 100ms | Total response time |
| RBS first load | ~500ms | One-time, lazy loaded |
| RBS lookup | < 10ms | After initial load |
| FlowAnalyzer | < 20ms | Scope-limited |
| Chain resolution | < 50ms | New, needs benchmarking |

### Caching & Performance Tasks
- [ ] Add TypeDB caching with AST node location as key
- [ ] Add `MethodSummary` cache (`MethodRef → MethodSummary`)
- [ ] Consider scope-level summary caching
- [ ] Implement timeout handling (Config values above)
- [ ] Benchmark hover response time in real projects

---

## Error Handling Strategy (Reference)

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
- [ ] Filter overloads at call-site:
  - [ ] Positional arg count mismatch
  - [ ] Required keyword missing
  - [ ] Known arg type mismatch (literals, etc.)

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

| Order | Task | Risk | Status |
|-------|------|------|--------|
| 1 | 7.2 Eliminate Duplicate Literal Inference | Low | Pending |
| 2 | 7.1 Split hover.rb | Medium | Pending |
| 3 | 7.3 Cache RBSProvider | Low | Pending |
| 4 | 7.4 Reduce Verbose Type References | Low | Pending |
| 5 | 7.5-7.7 Minor cleanups | Low | Pending |

**Rationale:** Start with duplication elimination (7.2) as it's lower risk and enables cleaner split of hover.rb (7.1)
