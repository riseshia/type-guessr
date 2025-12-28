# TypeGuessr TODO

> Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

**Current Status:**
- ✅ Phase 5 (MVP Hover Enhancement): COMPLETED
- ✅ Phase 6 (Heuristic Fallback): COMPLETED
- ✅ Phase 7 (Code Quality & Refactoring): COMPLETED (7.6 optional, low priority)
- ✅ Phase 8 (Generic & Block Type Inference): COMPLETED
- ✅ Phase 9 (Constant Alias Support): COMPLETED
- ✅ Phase 10 (User-Defined Method Return Type Inference): COMPLETED
- All 327 tests passing (7 pending: 1 non-critical, 6 RubyIndexer integration tests)

---

## Remaining Low-Priority Items

### 7.6 Replace `__send__` Protected Method Access (Optional)

**Problem:** `node.location.__send__(:source)` accesses protected method - fragile.

**Solution:**
- [ ] Investigate if Prism provides public API for accessing source
- [ ] If not, document why this workaround is necessary
- [ ] Consider caching source at initialization if possible

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

### Inverted Index
- [ ] Build method name → owner type candidates index
- [ ] Optimize heuristic lookup performance

### UX Improvements
- [ ] Fold/summarize excessive overloads in hover
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
