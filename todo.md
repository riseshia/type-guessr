# TypeGuessr TODO

> Items are ordered by priority (top = highest).
> MVP Goal: Show type on Hover event (practical type flowing without full rigor)

**Current Status:**
- ✅ Phase 5 (MVP Hover Enhancement): COMPLETED
- ✅ Phase 6 (Heuristic Fallback): COMPLETED
- 🔄 Phase 7 (Code Quality & Refactoring): ALMOST COMPLETE (only 7.6 remaining)
- ✅ Phase 8 (Generic & Block Type Inference): COMPLETED
- ✅ Phase 9 (Constant Alias Support): COMPLETED
- ✅ Phase 10 (User-Defined Method Return Type Inference): COMPLETED
- All 327 tests passing (7 pending: 1 non-critical, 6 RubyIndexer integration tests)

---

## Phase 7: Code Quality & Refactoring (Current Priority)

### 7.1 Split hover.rb ✅

**Problem:** `hover.rb` was 580 lines with multiple responsibilities mixed together.

**Completed:**
- [x] Extract `DefNodeFinder` to `lib/type_guessr/core/def_node_finder.rb` (commit: `dd4d542`)
- [x] Extract literal type inference to `lib/type_guessr/core/literal_type_analyzer.rb` (Phase 7.2)
- [x] Extract call chain resolution to `CallChainResolver` (commit: `7c11e8a`)
- [x] Hover is now a thin coordinator that delegates to specialized handlers

**Result:** hover.rb significantly reduced and responsibilities properly separated

### 7.2 Eliminate Duplicate Literal Type Inference ✅

**Completed:** Created `LiteralTypeAnalyzer.infer(node)` in core layer and consolidated literal type inference across the codebase.

**Commit:** Phase 8.1 (`a19ad62`)

### 7.3 Cache RBSProvider Instance ✅

**Completed:** Added memoized `rbs_provider` method in Hover class, replacing 3 separate instantiations.

**Commit:** `efed41e`

### 7.4 Reduce Verbose Type References ✅

**Problem:** Fully qualified type names repeated throughout codebase:
- `::TypeGuessr::Core::Types::Unknown.instance` (13+ occurrences)
- `::TypeGuessr::Core::Types::ClassInstance.new("...")` (20+ occurrences)

**Completed:** Added private constant aliases in integration layer classes:
- [x] `Types`, `TypeFormatter`, `LiteralTypeAnalyzer`, `FlowAnalyzer`, `DefNodeFinder`, `RBSProvider` in hover.rb
- [x] `Types`, `TypeFormatter` in hover_content_builder.rb
- [x] `Types`, `ScopeResolver` in variable_type_resolver.rb
- [x] `ASTAnalyzer`, `VariableIndex` in runtime_adapter.rb
- [x] `TypeFormatter` in type_inferrer.rb
- [x] `VariableIndex` in debug_server.rb

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

### 7.7 Refactor Similar FlowVisitor Methods ✅

**Problem:** `visit_local_variable_or_write_node` and `visit_local_variable_and_write_node` in flow_analyzer.rb are nearly identical (lines 129-161).

**Solution:**
- [x] Extract common logic to private helper method
- [x] Keep operator-specific semantics in visitor methods

**Completed:** Extracted `handle_compound_assignment` helper. Reduced code from ~45 lines to ~20 lines.

**Commit:** `b40bcd4`

### 7.8 Refactor UserMethodReturnResolver Test (Medium Priority)

**Problem:** `spec/type_guessr/core/user_method_return_resolver_spec.rb` has too many RuboCop disables:
- `RSpec/MultipleMemoizedHelpers` - 6 let statements (limit is 5)
- `RSpec/VerifiedDoubles` - Using `double()` instead of verified doubles
- `RSpec/ContextWording` - Context descriptions don't follow conventions

**Solution:**
- [ ] Reduce memoized helpers by inlining type constants or grouping related ones
- [ ] Use `instance_double()` for IndexAdapter and Entry instead of `double()`
- [ ] Rename contexts to follow conventions:
  - "caching behavior" → "when caching results"
  - "depth limit" → "when depth limit is exceeded"
- [ ] Remove `# rubocop:disable` and `# rubocop:enable` comments

**Files:**
- `spec/type_guessr/core/user_method_return_resolver_spec.rb`

---

## Phase 8: Generic & Block Type Inference

Goal: Enable type inference for generic containers and block parameters.

### 8.1 Array Literal Element Type Inference (Foundation) ✅

**Problem:** `[1,2,3]` is inferred as `Array` instead of `Array[Integer]`.

**Implemented:**
- [x] Created `LiteralTypeAnalyzer` class with array element type inference
- [x] Homogeneous arrays → typed (e.g., `[1,2,3]` → `Array[Integer]`)
- [x] Mixed arrays (2-3 types) → Union element type
- [x] Mixed arrays (4+ types) → Unknown element type
- [x] Max 5 samples for performance, max 1 nesting depth

**Commit:** `a19ad62`

### 8.2 RBSProvider Generic Type Preservation ✅

**Problem:** `rbs_type.args` is ignored, so `Array[Integer]` becomes just `Array`.

**Implemented:**
- [x] Handle `rbs_type.args` in `convert_class_instance`
- [x] Convert `Array[T]` to `Types::ArrayType` with element type
- [x] Type variables (Elem, etc.) return Unknown for now

**Commit:** `5e8b12d`

### 8.3 Block Parameter Type Inference ✅

**Problem:** In `a.map { |num| ... }`, `num` type is unknown even when `a` is `Array[Integer]`.

**Implemented:**

#### 8.3.1 Block Parameter Type Query API ✅
- [x] Added `RBSProvider#get_block_param_types(class_name, method_name)`
- [x] Added `RBSProvider#get_block_param_types_with_substitution` with type variable binding
- [x] Access block signature via `method_type.block`
- **Commit:** `31ba88a`

#### 8.3.2 Type Variable Substitution ✅
- [x] Implemented in `rbs_type_to_types_with_substitution`
- [x] Binds `Elem` → actual element type from ArrayType

#### 8.3.3 Hover Integration ✅
- [x] Added `try_block_parameter_inference` in hover.rb
- [x] Uses `node_context.call_node` to find enclosing call
- [x] Resolves receiver type and extracts element type for substitution
- [x] Returns inferred block parameter type in hover
- **Commit:** `138da9b`

**Working Examples:**
- `arr.each { |num| }` → `num: Integer` (when `arr = [1,2,3]`)
- `names.map { |name| }` → `name: String` (when `names = ["a","b"]`)
- `text.each_char { |char| }` → `char: String`

### 8.4 Hash Literal Type Inference ✅

**Problem:** `{a: 1}` is inferred as `Hash` instead of typed hash.

**Implemented:**
- [x] Symbol-keyed hashes → `HashShape` with field types
- [x] Empty hash → generic `Hash`
- [x] String/other keys → generic `Hash` (fallback)
- [x] Non-literal values → `Unknown` type for that field
- [x] Nested arrays/hashes supported
- [x] Falls back to `Hash` when >15 fields

**Commit:** `cec5fed`

**Examples:**
- `{ name: "Alice", age: 30 }` → `{ name: String, age: Integer }`
- `{ items: [1,2], active: true }` → `{ items: Array[Integer], active: TrueClass }`

### 8.5 Method Parameter Type Inference from Usage ✅

**Problem:** Required parameters show as `untyped` even when usage patterns are available.

**Implemented:**
- [x] Collect method calls on parameters directly from method body AST
- [x] Use TypeMatcher to find candidate types based on method usage
- [x] Show inferred type in both parameter hover and method signature
- [x] Return Union type when multiple types match
- [x] Added `ParameterMethodCallVisitor` for AST traversal

**Features:**
- Hover on required parameter → shows inferred type
- Hover on DefNode → signature includes inferred parameter types
- Handles ambiguous cases with Union types

**Examples:**
```ruby
def publish(recipe)
  recipe.validate!      # These method calls
  recipe.update(...)    # are collected
  recipe.notify_followers
end
# Hovering on "recipe" → Guessed type: Recipe
```

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
- ~~Parameter type inference from usage patterns~~ → Moved to Phase 8.5

### Inverted Index
- [ ] Build method name → owner type candidates index
- [ ] Optimize heuristic lookup performance

### UX Improvements
- [ ] Fold/summarize excessive overloads in hover
- ~~Block type notation~~ → Moved to Phase 8.3, 8.6
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

### Phase 7 (Code Quality)

| Order | Task | Risk | Status |
|-------|------|------|--------|
| 1 | 7.2 Eliminate Duplicate Literal Inference | Low | ✅ Done |
| 2 | 7.1 Split hover.rb | Medium | ✅ Done |
| 3 | 7.3 Cache RBSProvider | Low | ✅ Done |
| 4 | 7.4 Reduce Verbose Type References | Low | ✅ Done |
| 5 | 7.5 Extract Magic Numbers | Low | ✅ Done |
| 6 | 7.8 Refactor UserMethodReturnResolver Test | Medium | ✅ Done |
| 7 | 7.7 Refactor FlowVisitor Methods | Low | ✅ Done |
| 8 | 7.6 Replace __send__ Protected Method Access | Low | Pending |

**Rationale:** Start with duplication elimination (7.2) as it's lower risk and enables cleaner split of hover.rb (7.1). 7.8 added to remove RuboCop disables from Phase 10 test.

### Phase 8 (Generic & Block Types)

| Order | Task | Difficulty | Status |
|-------|------|------------|--------|
| 1 | 8.1 Array element type inference | Easy | ✅ Done |
| 2 | 8.2 RBSProvider generic preservation | Easy | ✅ Done |
| 3 | 8.3 Block parameter type inference | Medium | ✅ Done |
| 4 | 8.4 Hash type inference | Easy | ✅ Done |
| 5 | 8.5 Method parameter inference | Medium | ✅ Done |

**Rationale:** 8.1 and 8.2 form the foundation for generic type flow. 8.3 (block params) is the most impactful feature and depends on both.

---

## Phase 9: Constant Alias Support

Goal: Enable type inference through constant aliases like `Types = ::TypeGuessr::Core::Types`.

### Specification

**Supported Patterns:**
- `CONST = ::Foo::Bar` (constant path on RHS)
- `CONST = Foo` (constant read on RHS)
- Nested: `module M; Types = ::Core::Types; end`

**Not Supported:**
- Method call results: `Config = Rails.config`
- Conditional assignment: `Types ||= Foo`
- Dynamic assignment: `Types = some_method`

**Use Cases:**
1. `.new` call type inference: `Types::ClassInstance.new` → resolve `Types` first
2. Hover info: Show original constant when hovering on alias
3. Method call analysis: Track calls through aliased constants

### 9.1 ConstantIndex Design ✅

**Problem:** No storage for constant alias mappings.

**Implementation:**
- [x] Add `ConstantIndex` class (singleton, similar to VariableIndex)
- [x] Data structure:
  ```ruby
  {
    file_path => {
      "RubyLsp::TypeGuessr::Types" => {
        target: "::TypeGuessr::Core::Types",
        line: 107,
        column: 6
      }
    }
  }
  ```
- [x] Methods: `add_alias`, `resolve_alias`, `clear_file`

**Difficulty:** Easy
**Commit:** `30637aa`

### 9.2 AST Analyzer: Constant Tracking ✅

**Problem:** `ConstantWriteNode` and `ConstantPathWriteNode` are not visited.

**Implementation:**
- [x] Add `visit_constant_write_node` handler
- [x] Add `visit_constant_path_write_node` handler
- [x] Extract target constant name from RHS (only if ConstantReadNode or ConstantPathNode)
- [x] Generate FQN using current nesting context
- [x] Store in ConstantIndex

**Difficulty:** Easy
**Commit:** `30637aa`

### 9.3 Alias Resolution in Type Inference ✅

**Problem:** `Types::ClassInstance.new` doesn't resolve `Types` alias.

**Implementation:**
- [x] Update `extract_class_name_from_receiver` in AST Analyzer
- [x] When encountering ConstantReadNode, check ConstantIndex first
- [x] Recursively resolve aliases (with depth limit MAX_ALIAS_DEPTH=5)
- [x] Apply to `.new` call type extraction in both AST Analyzer and Hover

**Difficulty:** Medium
**Commit:** `30637aa`

### 9.4 Hover Support for Constant Aliases (Optional)

**Problem:** No hover info for constant aliases.

**Implementation:**
- [ ] Add `ConstantReadNode` to HOVER_NODE_TYPES (if not already)
- [ ] Show alias target in hover: `Types → ::TypeGuessr::Core::Types`
- [ ] Include definition location link

**Difficulty:** Easy
**Status:** Optional - can be added in future if needed

### Implementation Priority

| Order | Task | Difficulty | Dependencies |
|-------|------|------------|--------------|
| 1 | 9.1 ConstantIndex Design | Easy | None |
| 2 | 9.2 AST Constant Tracking | Easy | 9.1 |
| 3 | 9.3 Alias Resolution | Medium | 9.2 |
| 4 | 9.4 Hover Support | Easy | 9.2 |

**Rationale:** 9.1 and 9.2 establish the foundation. 9.3 provides the core value (type inference through aliases). 9.4 is a nice-to-have UX improvement.

---

## Phase 10: User-Defined Method Return Type Inference

Goal: Infer return types for user-defined methods when hovering on variables assigned from method calls.

### Background

Currently, `cc = c.eat` returns `Unknown` because `Animal#eat` is not in RBS. We need to infer the return type from the method definition itself.

### 10.1 UserMethodReturnResolver Class ✅

**Problem:** No way to get return type for user-defined methods.

**Implementation:**
- [x] Create `lib/type_guessr/core/user_method_return_resolver.rb`
- [x] Accept RubyIndexer to find method definitions
- [x] Use `FlowAnalyzer` to infer return type on-demand
- [x] Cache results to avoid repeated analysis
- [x] Handle recursion with depth limit (max 5 levels)

**API:**
```ruby
resolver.get_return_type("Animal", "eat") # => Types::ClassInstance.new("NilClass")
```

**Difficulty:** Medium
**Commit:** (Phase 10 implementation)

### 10.2 Hover Integration ✅

**Problem:** Hover doesn't try user-defined method resolution.

**Implementation:**
- [x] Modify `resolve_call_chain` in hover.rb
- [x] After RBS returns Unknown, try UserMethodReturnResolver
- [x] Return inferred type from user-defined method

**Difficulty:** Easy
**Commit:** (Phase 10 implementation)

### 10.3 Read Method Source from Index Entry ✅

**Problem:** Need to get method source code from RubyIndexer entry.

**Implementation:**
- [x] Use entry.location to get file path and line range
- [x] Read method source from file
- [x] Handle errors gracefully (file not found, etc.)

**Difficulty:** Easy
**Commit:** (Phase 10 implementation)

### Implementation Priority

| Order | Task | Difficulty | Dependencies |
|-------|------|------------|--------------|
| 1 | 10.1 UserMethodReturnResolver | Medium | None |
| 2 | 10.3 Read Method Source | Easy | 10.1 |
| 3 | 10.2 Hover Integration | Easy | 10.1 |

**Expected Outcome:**
```ruby
class Animal
  def eat; end
end

c = Animal.new
cc = c.eat
# Hover on cc → Guessed type: NilClass
```
