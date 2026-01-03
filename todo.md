# TypeGuessr TODO

> Priority-based task management for TypeGuessr development.
> Items ordered by priority: P0 (Production Blockers) → P1 (High Value) → P2 (Quality) → P3 (Future)

---

## 📊 Current Status (2026-01-03)

**Test Results:** 348/349 tests passing (99.7%), 1 pending

### ✅ Recently Completed

**Chain-based Lazy Type Inference Architecture**
- Replaced `VariableIndex`, `ASTAnalyzer`, `CallChainResolver` with unified Chain system
- Chain extraction during parsing, lazy type resolution at hover time
- Full support for: literals, `.new` calls, variables, parameters, block parameters, self nodes
- Control flow handled via Chain::If and Chain::Or links
- Depth limit (5) to prevent infinite recursion

**Method Chain Type Resolution**
- Recursive chain resolution for hover on chained methods (`str.chars.first`)
- Block presence detection for correct RBS signature selection
- Type variable substitution for generics (`Array[Integer]#map` → `Enumerator[Integer]`)
- Enumerator pattern support for block parameter inference

**RubyIndexer Test Source Indexing**
- Test sources now indexed in ruby-lsp's RubyIndexer via `index_single()`
- Type definition links work with inline class definitions in tests
- `UserMethodReturnResolver` connected to `ChainResolver` for user-defined method analysis
- Fixed `type_entries` key lookup in `HoverContentBuilder` (type object vs string)

**Method Return Type Chain Storage** (2026-01-03)
- Store method return type Chains during AST parsing in ChainIndex
- ChainExtractor collects return Chains from method bodies (last expression + return statements)
- Chain::Call fallback: RBS → UserMethodReturnResolver → ChainIndex
- Empty method body correctly infers NilClass
- Multiple return paths create Union types
- All 5 user-defined method integration tests now passing ✅

### ⚠️ Known Limitations

None currently - all planned features working as expected.

---

## 🟠 P1: High Value Features & Performance

> Direct impact on user experience. Performance improvements, new features, and critical refactoring.

### 4. Hash Incremental Field Addition

**Problem:** Cannot track hash field additions via `[]=` assignments.

**Current Behavior:**
```ruby
a = { a: 1 }   # → { a: Integer }
a[:b] = 3      # Type not updated
a              # Still shows { a: Integer }, should be { a: Integer, b: Integer }
```

**Why Important:**
- Hashes are fundamental data structures in Ruby
- Common pattern: building hashes incrementally
- HashShape infrastructure already exists
- High practical value for real-world code

**Current Support:**
- ✅ Hash literal inference works: `{ a: 1, b: "str" }` → `{ a: Integer, b: String }`
- ❌ No tracking of element writes via `[]=`
- ❌ No type updates after initial definition

**Locations:**
- `lib/type_guessr/core/ast_analyzer.rb` - No visitor for index writes
- `lib/type_guessr/core/variable_index.rb` - No type merge/update logic
- `lib/type_guessr/core/types.rb` - HashShape exists but immutable

**Solution (Phase 2 - Sequential Writes):**

Scope: Handle simple sequential assignments in same scope, no control flow.

1. **Add AST visitor for index writes:**
   ```ruby
   # In ASTAnalyzer
   def visit_index_operator_write_node(node)
     # a[:b] = 3
     # - receiver: LocalVariableReadNode (a)
     # - index: SymbolNode (:b)
     # - value: IntegerNode (3)

     return super unless node.index.is_a?(Prism::SymbolNode)  # Only symbol keys

     receiver_var = extract_variable_name(node.receiver)
     return super unless receiver_var

     key = node.index.value.to_sym
     value_type = analyze_value_type(node.value)

     # Store field addition info
     store_hash_field_addition(
       var_name: receiver_var,
       key: key,
       value_type: value_type,
       line: node.location.start_line,
       column: node.location.start_column
     )

     super
   end
   ```

2. **Add field addition tracking to VariableIndex:**
   ```ruby
   # New storage for hash field additions
   @hash_field_additions = {
     instance_variables: {},
     local_variables: {},
     class_variables: {}
   }

   # Structure: { file_path => { scope_id => { var_name => [additions] } } }
   # additions = [{ key: :b, type: Integer, line: 2, column: 0 }]

   def add_hash_field_addition(file_path:, scope_type:, scope_id:, var_name:, key:, value_type:, line:, column:)
     # Store field addition chronologically
   end

   def get_hash_fields_at_location(file_path:, scope_type:, scope_id:, var_name:, max_line:)
     # Collect all field additions up to max_line
     # Merge with base HashShape from initial assignment
   end
   ```

3. **Add type merging logic:**
   ```ruby
   # In TypeResolver or new HashTypeMerger class
   def merge_hash_type(base_type, field_additions)
     return base_type unless base_type.is_a?(Types::HashShape)

     # Start with base fields
     merged_fields = base_type.fields.dup

     # Apply field additions chronologically
     field_additions.each do |addition|
       merged_fields[addition[:key]] = addition[:type]
     end

     Types::HashShape.new(merged_fields)
   end
   ```

4. **Integrate into TypeResolver:**
   ```ruby
   def get_direct_type(variable_name:, hover_line:, scope_type:, scope_id:, file_path: nil)
     # ... existing logic to get base type

     # If base type is HashShape, check for field additions
     if base_type.is_a?(Types::HashShape)
       field_additions = @index.get_hash_fields_at_location(
         file_path: file_path,
         scope_type: scope_type,
         scope_id: scope_id,
         var_name: variable_name,
         max_line: hover_line
       )

       base_type = merge_hash_type(base_type, field_additions) if field_additions.any?
     end

     base_type
   end
   ```

**Limitations (Intentional):**
- ❌ Control flow not analyzed (if/else branches)
- ❌ String/dynamic keys not supported (only Symbol keys)
- ❌ Field deletions not tracked (`hash.delete(:key)`)
- ❌ Spread/merge operations not tracked (`hash.merge(...)`)
- ✅ Simple sequential additions in same scope: SUPPORTED

**Test Cases:**
```ruby
# Basic sequential addition
a = {}
a[:x] = 1
a[:y] = "str"
a  # → { x: Integer, y: String }

# With initial fields
a = { a: 1 }
a[:b] = "str"
a  # → { a: Integer, b: String }

# Field override
a = { x: 1 }
a[:x] = "str"
a  # → { x: String } (last write wins)

# Symbol keys only
a = {}
a["str_key"] = 1  # NOT tracked, fall back to Hash
a  # → Hash

# Scope isolation
def foo
  a = {}
  a[:x] = 1
end

def bar
  a = {}
  a[:y] = 2
end
# Each method has separate hash types
```

**Tasks:**
- [ ] Write failing integration tests (TDD)
  - `spec/integration/hover_spec.rb` - Add hash field addition examples
  - `spec/type_guessr/core/ast_analyzer_spec.rb` - Index write visitor
  - `spec/type_guessr/core/variable_index_spec.rb` - Field addition storage
- [ ] Add `visit_index_operator_write_node` to ASTAnalyzer
- [ ] Add hash field addition storage to VariableIndex
- [ ] Implement type merging logic
- [ ] Integrate into TypeResolver
- [ ] Document limitations in docs/inference_rules.md

**Future (Phase 3 - Control Flow):**
```ruby
# Not in scope for Phase 2
a = {}
if condition
  a[:x] = 1
else
  a[:x] = "str"
end
a  # → { x: Integer | String } (requires control flow analysis)
```

**Files to Modify:**
- `lib/type_guessr/core/ast_analyzer.rb`
- `lib/type_guessr/core/variable_index.rb`
- `lib/type_guessr/core/type_resolver.rb`
- `spec/integration/hover_spec.rb`
- `spec/type_guessr/core/ast_analyzer_spec.rb`
- `spec/type_guessr/core/variable_index_spec.rb`

---

### 5. ✅ User-Defined Method Return Type Inference (COMPLETED)

**Status:** ✅ COMPLETED via ChainIndex-based approach (2026-01-03)

**Solution Implemented:**

Instead of integrating UserMethodReturnResolver into FlowAnalyzer, we implemented a ChainIndex-based approach:

1. **ChainExtractor** collects method return Chains during AST parsing:
   - `visit_def_node`: Extracts last expression Chain + return statement Chains
   - `visit_return_node`: Collects explicit return Chains
   - Empty method bodies correctly infer NilClass

2. **ChainIndex** stores method return Chains:
   - Key: `ClassName#method_name`
   - Value: Array of Chains (for multiple return paths)

3. **Chain::Call** fallback resolution order:
   - RBS (stdlib/gems) → UserMethodReturnResolver (file-based) → ChainIndex (AST-based)
   - Multiple return Chains are merged into Union types

**Results:**
- ✅ All 5 integration tests passing
- ✅ Works with in-memory test sources (no File.readlines dependency)
- ✅ User-defined method return types correctly inferred
- ✅ Union types for multiple return paths

**Example:**
```ruby
class Animal
  def name
    "Dog"  # → String
  end

  def value
    return "string" if condition
    42  # → String | Integer
  end
end

animal = Animal.new
result = animal.name  # ✅ Infers String
```

**Files Modified:**
- `lib/type_guessr/core/chain_index.rb` - Method return Chain storage
- `lib/type_guessr/core/chain_extractor.rb` - Return Chain extraction
- `lib/type_guessr/core/chain_context.rb` - Interface for Chain lookup
- `lib/type_guessr/core/chain/call.rb` - ChainIndex fallback
- `spec/integration/hover_spec.rb` - Enabled 5 previously skipped tests

---

## 🟡 P2: Quality Improvements

> Code quality and maintainability improvements. Important but can be deferred after P0/P1.

### 8. Performance Optimization (FlowAnalyzer Caching)

**Problem:** FlowAnalyzer re-parses AST on every hover without caching.

**Locations:**
- `lib/ruby_lsp/type_guessr/hover.rb:541-572` - Repeated AST parsing
- `lib/type_guessr/core/flow_analyzer.rb:15-19` - No result caching

**Why Important:**
- Hover latency target is <100ms (see Reference Documents)
- Current implementation may exceed target on large files
- User experience degrades with slow hover

**Current Issues:**

**FlowAnalyzer Repeated Parsing:**
```ruby
def try_flow_analysis(node)
  method_node = find_containing_method(node)
  source = method_node.slice
  analyzer = FlowAnalyzer.new
  result = analyzer.analyze(source)  # ⚠️ Re-parses every hover
end
```

**Impact:**
- Hover can take 100-200ms on large methods
- CPU usage spikes during typing
- Poor user experience

**Solution:**

**Add FlowAnalyzer Result Cache:**
```ruby
class FlowAnalyzerCache
  def initialize
    @cache = {}  # method_location => AnalysisResult
    @mutex = Mutex.new
  end

  def analyze(method_node)
    cache_key = [
      method_node.location.start_line,
      method_node.location.end_line,
      method_node.name
    ]

    @mutex.synchronize do
      @cache[cache_key] ||= FlowAnalyzer.new.analyze(method_node.slice)
    end
  end

  def clear_file(file_path)
    @mutex.synchronize do
      @cache.delete_if { |key, _| key[0].include?(file_path) }
    end
  end
end
```

**Tasks:**
- [ ] Add FlowAnalyzerCache with file-based invalidation
- [ ] Add TypeDB caching with AST node location as key
- [ ] Add `MethodSummary` cache (`MethodRef → MethodSummary`)
- [ ] Consider scope-level summary caching
- [ ] Implement timeout handling (see Reference Documents)
- [ ] Add performance benchmarks (`spec/performance/hover_response_spec.rb`)
- [ ] Measure before/after performance on real projects
- [ ] Benchmark hover response time in real projects
- [ ] Document cache invalidation strategy

**Expected Improvements:**
- FlowAnalyzer: 100-200ms → 1-5ms (cached)
- Overall hover: <100ms in 95% of cases

---

### 10. Variable Name-Based Type Inference

**Problem:** Not using variable naming conventions for type hints.

**Why Important:**
- Research shows 30% improvement in type inference accuracy
- Low implementation cost, high value
- Works well in combination with existing methods

**Approach:**
- [ ] Plural names (`users`, `items`) → Array type
- [ ] `_id`, `_count`, `_num` suffix → Integer type
- [ ] `_name`, `_title` suffix → String type
- [ ] `is_`, `has_`, `can_` prefix → Boolean (TrueClass | FalseClass)

**Reference:**
- "Sound, Heuristic Type Annotation Inference for Ruby" (2020) - reported 30% improvement

**Implementation:**
- [ ] Create `VariableNameAnalyzer` in Core layer
- [ ] Integrate with existing type inference pipeline
- [ ] Add fallback behavior (only use when other methods fail)
- [ ] Add tests for various naming patterns
- [ ] Document naming conventions in README

---

### 11. Extended Inference (Operations)

**Problem:** No type inference for operations like `+`, `*`, etc.

**Why Important:**
- Common patterns in Ruby code
- Improves completeness of type inference

**Approach:**
- [ ] Operations (`+`, `*`, etc.) type inference
  - `Integer + Integer → Integer`
  - `String + String → String`
  - `Array + Array → Array`
- [ ] Flow-sensitive refinement through branches/loops
  - `if x.is_a?(String)` → refine x type to String in then branch

**Implementation:**
- [ ] Add `OperationTypeInferrer` to handle binary operations
- [ ] Extend FlowAnalyzer to handle type refinements
- [ ] Add tests for common operation patterns

---

### 12. UX Improvements

**Problem:** Hover can show too much information or miss useful information.

**Why Important:**
- User experience degrades with information overload
- Missing useful features like project-specific RBS

**Tasks:**
- [ ] Fold/summarize excessive overloads in hover
  - Show first 3 overloads, then "... and N more"
- [ ] Project RBS loading from `sig/` folder
  - Load user-defined RBS signatures
- [ ] Filter overloads at call-site:
  - [ ] Positional arg count mismatch
  - [ ] Required keyword missing
  - [ ] Known arg type mismatch (literals, etc.)

---

### 13. Replace `__send__` Protected Method Access

**Problem:** `node.location.__send__(:source)` accesses protected method - fragile.

**Why Important:**
- Fragile dependency on implementation details
- Could break in future Prism versions

**Solution:**
- [ ] Investigate if Prism provides public API for accessing source
- [ ] If not, document why this workaround is necessary
- [ ] Consider caching source at initialization if possible

---

## 🟢 P3: Future Vision

> Long-term vision and extensibility. Can be deferred until core functionality is solid.

### 14. Memory Management Strategy (Deferred)

**Problem:** No memory limits for unbounded index growth.

**Location:** `lib/type_guessr/core/variable_index.rb`

**Current Status:** Deferred - needs real-world validation first.

**Why Deferred:**
- ruby-lsp's RubyIndexer is also unbounded - same approach
- TypeGuessr's additional memory overhead is minimal per variable (~300-500 bytes)
- No production evidence of memory issues yet
- LRU eviction would break index accuracy (incomplete index = broken type inference)

**If Needed Later:**
- sqlite3 offload preferred over LRU cache
  - Preserves data integrity (no eviction = no lost type info)
  - Enables warm start after process restart
  - Trade-off: I/O latency, increased complexity

**Prerequisites:**
- [ ] Measure actual memory usage in large projects (10k+ files)
- [ ] Compare overhead vs ruby-lsp base memory
- [ ] Document findings before implementation decision

---

### 15. Documentation Improvements

**Problem:** Missing architecture decisions and performance characteristics.

**Location:** Documentation files

**Why Important:**
- New contributors need context
- Maintainers need to understand trade-offs
- Users need to know performance expectations

**Current Gaps:**
- No ARCHITECTURE.md explaining design decisions
- No performance characteristics documented
- Threading model not explained
- Memory model not documented

**Impact:**
- Hard for new contributors to start
- Design rationale lost over time
- Users don't know what to expect

**Solution:**
- [ ] Create ARCHITECTURE.md:
  ```markdown
  # TypeGuessr Architecture

  ## Design Decisions

  ### Two-Layer Architecture

  **Core Layer** (`lib/type_guessr/core/`)
  - Framework-agnostic type inference logic
  - No LSP dependencies
  - Pure functional where possible
  - Testable in isolation

  **Integration Layer** (`lib/ruby_lsp/type_guessr/`)
  - LSP-specific adapters
  - Lifecycle management
  - Node context extraction

  **Why this separation?**
  - Enables reuse outside LSP (CLI, Rails integration)
  - Faster tests (no LSP setup needed)
  - Clear boundaries for testing

  ### Thread Safety Strategy

  **Singleton Indexes:**
  - VariableIndex: Mutex-protected, thread-safe
  - ConstantIndex: Mutex-protected, thread-safe
  - RBSProvider: Lazy-loaded, thread-safe initialization

  **Worker Threads:**
  - RuntimeAdapter spawns 4 worker threads for AST analysis
  - All index updates must be synchronized
  - No shared mutable state outside indexes

  ### Memory Management

  **Index Size Limits:**
  - MAX_FILES: 1000 files (configurable)
  - MAX_MEMORY_MB: 500 MB (configurable)
  - LRU eviction when limits reached

  **Growth Characteristics:**
  - O(n) where n = total lines of code
  - ~500 bytes per variable definition
  - ~100 bytes per method call

  ### Performance Characteristics

  **Indexing:**
  - Initial: O(n) where n = total LOC
  - Time: ~1000 files/second on modern CPU
  - Memory: ~0.5 MB per 1000 LOC

  **Hover:**
  - Lookup: O(1) hash access
  - Type matching: O(m) where m = method calls
  - Target: <100ms in 95% of cases

  **Caching Strategy:**
  - FlowAnalyzer results: Cached per method
  - TypeMatcher: Inverted index built once
  - RBS signatures: Lazy-loaded, never evicted

  ## Error Handling Contract

  **Core Layer:**
  - NEVER raises exceptions to caller
  - Returns Types::Unknown on error
  - Logs errors via TypeGuessr::Logger

  **Integration Layer:**
  - Can return nil for optional features
  - Catches all exceptions from Core
  - Falls back gracefully on error

  ## Testing Strategy

  **Unit Tests:**
  - Each Core class tested in isolation
  - Mock LSP dependencies in Integration layer

  **Integration Tests:**
  - Full LSP lifecycle tests
  - Real-world code samples

  **Performance Tests:**
  - Benchmark critical paths
  - CI fails if >10% regression
  ```

- [ ] Update README with performance expectations:
  ```markdown
  ## Performance

  TypeGuessr is designed for production use with these characteristics:

  - **Indexing:** ~1000 files/second
  - **Hover response:** <100ms in 95% of cases
  - **Memory usage:** ~500 bytes per variable, configurable limits
  - **Threading:** 4 worker threads for parallel indexing

  ### Configuration

  Tune performance via `.type-guessr.yml`:

  ```yaml
  performance:
    max_files: 1000           # LRU cache size
    max_memory_mb: 500        # Memory limit
    max_chain_depth: 5        # Method chain depth
  ```
  ```

**Tasks:**
- [ ] Create ARCHITECTURE.md with design rationale
- [ ] Document threading model and safety guarantees
- [ ] Document memory characteristics and limits
- [ ] Add performance expectations to README
- [ ] Document error handling contract
- [ ] Add troubleshooting guide

---

### 16. DSL Support

**Problem:** Limited support for Ruby DSLs.

**Why Important:**
- Many Ruby projects use DSLs heavily
- Basic support already exists via ruby-lsp-rails

**Current Status:**
- Basic support via ruby-lsp/ruby-lsp-rails indexer already working

**Tasks:**
- [ ] General Ruby DSL pattern support
- [ ] Extensible interface for custom type providers
- [ ] Rails DSL support (ActiveRecord::Relation deferred - complex)

---

### 17. Standalone API

**Problem:** Core library only usable within Ruby LSP.

**Why Important:**
- Enables CLI tools, Rails integration, etc.
- Makes library more versatile

**Tasks:**
- [ ] Add `TypeGuessr.analyze_file(file_path)` method
- [ ] Add `TypeGuessr::Project` class for caching indexes
- [ ] Add `TypeGuessr::Core::FileAnalyzer` for single-file workflow

**Context:**
- Goal: Make core library usable independently from Ruby LSP
- Enables CLI tools, Rails integration, etc.
- Blocked by: Core type model and TypeDB completion

---

## 📚 Reference Documents

### Response Time Targets

| Operation | Target | Notes |
|-----------|--------|-------|
| Hover response | < 100ms | Total response time |
| RBS first load | ~500ms | One-time, lazy loaded |
| RBS lookup | < 10ms | After initial load |
| FlowAnalyzer | < 20ms | Scope-limited |
| Chain resolution | < 50ms | New, needs benchmarking |
