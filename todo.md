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
- All tests passing (8 pending: 1 non-critical, 6 RubyIndexer integration, 1 Hash block param)

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

### Variable Name-Based Type Inference (Priority: High)
- [ ] Plural names (`users`, `items`) → Array type
- [ ] `_id`, `_count`, `_num` suffix → Integer type
- [ ] `_name`, `_title` suffix → String type
- Reference: "Sound, Heuristic Type Annotation Inference for Ruby" (2020) - reported 30% improvement

### DSL Support (Priority: Low)
- [ ] General Ruby DSL pattern support
- [ ] Extensible interface for custom type providers
- [ ] Rails DSL support (ActiveRecord::Relation deferred - complex)
- Note: Basic support via ruby-lsp/ruby-lsp-rails indexer already working

### Extended Inference
- [ ] Operations (`+`, `*`, etc.) type inference
- [ ] Flow-sensitive refinement through branches/loops

### Generic Block Parameter Type Inference (Priority: Medium)

**Current Limitation:**
- Only supports single type variable substitution (`Array[Elem]` → `Elem`)
- `Hash#each { |k, v| }` not supported (requires `K`, `V` substitution)

**Proposal: Generic Type Variable Substitution**

1. **Parse RBS Method Signature for Type Variables:**
   - Extract all type variables from method signature (e.g., `Hash[K, V]#each`)
   - Identify which type variables are used in block parameters

2. **Map Receiver Type to Type Variables:**
   - `Array[Integer]` → `{ Elem: Integer }`
   - `Hash[Symbol, String]` → `{ K: Symbol, V: String }`
   - `HashShape { name: String, age: Integer }` → `{ K: Symbol, V: String | Integer }`

3. **Substitute Block Parameter Types:**
   - Replace type variables in block signature with concrete types
   - `(K, V) -> void` + `{ K: Symbol, V: String }` → `(Symbol, String) -> void`

**Implementation Tasks:**
- [ ] Add `TypeVariableExtractor` to parse RBS method signatures
- [ ] Extend `get_block_param_types_with_substitution` to accept multiple type variables (Hash)
- [ ] Add type variable mapping for `Hash` and `HashShape` types
- [ ] Update `try_block_parameter_inference` to extract multiple type variables
- [ ] Add integration tests for `Hash#each`, `Hash#map`, etc.

**References:**
- `lib/ruby_lsp/type_guessr/hover.rb:477-516` - Current implementation
- `lib/type_guessr/core/rbs_provider.rb:86-133` - Type substitution logic

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
