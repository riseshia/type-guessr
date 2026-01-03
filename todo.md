# TypeGuessr TODO

> Priority-based task management for TypeGuessr development.
> Items ordered by priority: P0 (Production Blockers) → P1 (High Value) → P2 (Quality) → P3 (Future)

## 🟠 P1: High Value Features & Performance

> Direct impact on user experience. Performance improvements, new features, and critical refactoring.

### 4. Performance Optimization (Inverted Index + Caching)

**Problem:** Multiple performance bottlenecks without caching.

**Locations:**
- `lib/ruby_lsp/type_guessr/type_matcher.rb:31-69` - O(n) linear search
- `lib/ruby_lsp/type_guessr/hover.rb:541-572` - Repeated AST parsing
- `lib/type_guessr/core/flow_analyzer.rb:15-19` - No result caching

**Why Important:**
- Hover latency target is <100ms (see Reference Documents)
- Current implementation may exceed target on large files
- User experience degrades with slow hover

**Current Issues:**

1. **TypeMatcher Linear Search:**
```ruby
def find_matching_types(method_names)
  all_owners = method_names.flat_map do |method_name|
    entries = @adapter.method_entries(method_name)  # ⚠️ O(n) search per method
    entries.filter_map { |entry| entry.owner&.name }
  end.uniq
end
```

2. **FlowAnalyzer Repeated Parsing:**
```ruby
def try_flow_analysis(node)
  method_node = find_containing_method(node)
  source = method_node.slice
  analyzer = FlowAnalyzer.new
  result = analyzer.analyze(source)  # ⚠️ Re-parses every hover
end
```

**Impact:**
- Hover can take 200-500ms on large methods
- CPU usage spikes during typing
- Poor user experience

**Solution:**

1. **Add Inverted Index to TypeMatcher:**
```ruby
class TypeMatcher
  def initialize(index)
    @adapter = IndexAdapter.new(index)
    @method_to_owners = build_inverted_index  # Build once
  end

  private

  def build_inverted_index
    # Create: method_name => Set[owner_name]
    # O(m) build time, O(1) lookup
    index = Hash.new { |h, k| h[k] = Set.new }
    # ... populate from @adapter
    index
  end

  def find_matching_types(method_names)
    # Use pre-built index instead of linear search
    candidates = method_names.map { |m| @method_to_owners[m] }
                              .reduce(&:&)  # Set intersection
    # ... rest of logic
  end
end
```

2. **Add FlowAnalyzer Result Cache:**
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
- [ ] Implement inverted index in TypeMatcher
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
- TypeMatcher: 50-100ms → 5-10ms
- FlowAnalyzer: 100-200ms → 1-5ms (cached)
- Overall hover: <100ms in 95% of cases

---

### 5. Block Return Type Analysis

**Problem:** Methods with blocks like `map`, `select` return `Unknown` instead of proper types.

```ruby
a = [1,2,3]
b = a.map do |num|
  num * 2
end
b #=> Actual: Unknown, Expected: Array[Integer]
```

**Root Cause:**
- RBS defines `Array#map` as `[U] { (Elem) -> U } -> Array[U]`
- Type variable `U` cannot be resolved without analyzing the block's return type
- `RBSProvider.rbs_type_to_types` returns `Unknown` for type variables

**Locations:**
- `lib/type_guessr/core/rbs_provider.rb:152-154` - Type variable handling
- `lib/type_guessr/core/type_resolver.rb:194-205` - `apply_method_chain`
- `lib/type_guessr/core/ast_analyzer.rb:419-438` - Call assignment tracking

**Why Important:**
- `map`, `select`, `filter` are extremely common in Ruby
- Current inference misses many type opportunities
- Block parameter types already work (via `get_block_param_types_with_substitution`)

**Solution:**

1. **Create BlockReturnAnalyzer** (new file):
   ```ruby
   # lib/type_guessr/core/block_return_analyzer.rb
   class BlockReturnAnalyzer
     # Analyze block's last expression to infer return type
     def analyze(block_node, context = {})
       # - Extract last expression from block body
       # - Use LiteralTypeAnalyzer for literals
       # - Use RBS for method calls on block parameters
       # - Return NilClass for empty blocks
     end
   end
   ```

2. **Extend RBSProvider** with `get_method_return_type_with_block`:
   ```ruby
   def get_method_return_type_with_block(class_name, method_name, block_return_type:, elem: nil)
     # 1. Get method signature
     # 2. Substitute type variable U with block_return_type
     # 3. Substitute Elem with receiver's element type
   end
   ```

3. **Extend VariableIndex** for block call assignments:
   - `add_block_call_assignment(receiver_var:, method_name:, block_return_type:)`
   - `find_block_call_assignment_at_location(...)`

4. **Extend ASTAnalyzer** to detect blocks:
   ```ruby
   def store_call_assignment_if_applicable(...)
     if value.block.is_a?(Prism::BlockNode)
       store_block_call_assignment(...)  # NEW path
     else
       # existing logic
     end
   end
   ```

5. **Extend TypeResolver** with `infer_type_from_block_call_assignment`:
   - Resolve receiver type
   - Call `RBSProvider.get_method_return_type_with_block`

**Tasks:**
- [ ] Write failing tests first (TDD)
  - `spec/type_guessr/core/block_return_analyzer_spec.rb`
  - `spec/type_guessr/core/rbs_provider_spec.rb` (additions)
  - `spec/integration/hover_spec.rb` (additions)
- [ ] Create `lib/type_guessr/core/block_return_analyzer.rb`
- [ ] Add `get_method_return_type_with_block` to RBSProvider
- [ ] Add block call assignment storage to VariableIndex
- [ ] Update ASTAnalyzer to detect and track blocks
- [ ] Integrate into TypeResolver

**Test Cases:**
```ruby
# Integration tests
"b = a.map { |n| n * 2 }" → Array[Integer]
"b = a.map { |n| n.to_s }" → Array[String]
"b = a.select { |n| n > 0 }" → Array[Integer]  # select preserves element type
"b = a.map { }" → Array[NilClass]
```

**Limitations:**
- Conditional returns (if/else branches) → Union not supported
- Complex control flow (loop, exception) → Not analyzed
- User-defined method calls in block → Unknown if no RBS

**Files to Modify:**
- `lib/type_guessr/core/block_return_analyzer.rb` (NEW)
- `lib/type_guessr/core/rbs_provider.rb`
- `lib/type_guessr/core/variable_index.rb`
- `lib/type_guessr/core/ast_analyzer.rb`
- `lib/type_guessr/core/type_resolver.rb`

---

### 6. VariableIndex Structure Improvement

**Problem:** Deep nested hash structure is fragile and hard to reason about.

**Location:** `lib/type_guessr/core/variable_index.rb:19-28`

**Why Important:**
- Complex data structure increases bug risk
- No type safety
- Hard to refactor
- Performance characteristics unclear
- Prerequisite for #2 (Memory Management)

**Current Structure:**
```ruby
@index = {
  instance_variables: {
    "/path/to/file.rb" => {
      "ClassName#method" => {
        "var_name" => {
          "10:5" => [
            { method: "foo", line: 11, column: 3 },
            { method: "bar", line: 12, column: 3 }
          ]
        }
      }
    }
  },
  local_variables: { ... },
  class_variables: { ... }
}
```

**Problems:**
- 5 levels of nesting
- Easy to make nil-access errors
- Verbose access patterns: `@index.dig(scope_type, file_path, scope_id, var_name, def_key)`
- Hard to add indexes (e.g., by line number)

**Impact:**
- Bugs in edge cases (missing nil checks)
- Performance issues (can't add secondary indexes)
- Hard to evolve data model

**Solution:**
- [ ] Introduce Value Objects for type safety:
  ```ruby
  # New classes
  class VariableDefinition
    attr_reader :file_path, :scope_type, :scope_id, :var_name, :line, :column

    def initialize(file_path:, scope_type:, scope_id:, var_name:, line:, column:)
      @file_path = file_path
      @scope_type = scope_type
      @scope_id = scope_id
      @var_name = var_name
      @line = line
      @column = column
      freeze
    end

    def key
      "#{file_path}:#{scope_type}:#{scope_id}:#{var_name}:#{line}:#{column}"
    end

    def ==(other)
      key == other.key
    end

    def hash
      key.hash
    end
  end

  class MethodCall
    attr_reader :method_name, :line, :column

    def initialize(method_name:, line:, column:)
      @method_name = method_name
      @line = line
      @column = column
      freeze
    end
  end

  # Simplified index structure
  class VariableIndex
    def initialize
      @definitions = {}        # VariableDefinition => true (set)
      @method_calls = {}       # VariableDefinition => [MethodCall]
      @types = {}              # VariableDefinition => Types::Type
      @call_assignments = {}   # VariableDefinition => CallAssignmentInfo

      # Secondary indexes for fast lookup
      @by_file = Hash.new { |h, k| h[k] = Set.new }  # file_path => Set[VariableDefinition]
      @by_location = {}        # "file:line:var" => VariableDefinition

      @mutex = Mutex.new
    end
  end
  ```

**Benefits:**
- Type safety (can't mix up parameters)
- Clear data model
- Easy to add indexes
- Simpler lookup code
- Immutable value objects (thread-safe)

**Tasks:**
- [ ] Create VariableDefinition, MethodCall, CallAssignmentInfo classes
- [ ] Refactor VariableIndex to use value objects
- [ ] Update all callers to use new API
- [ ] Add tests for new structure
- [ ] Measure performance impact

**Migration Strategy:**
1. Add new classes alongside existing code
2. Deprecate old methods
3. Update callers incrementally
4. Remove old code after full migration

---

### 7. Hover.rb Complexity Exceeds Limits

**Problem:** Single file with too many responsibilities (605 lines).

**Location:** `lib/ruby_lsp/type_guessr/hover.rb`

**Why Important:**
- Hard to understand and modify
- Multiple reasons to change (violates SRP)
- Testing is complex
- Code navigation is difficult

**Current Responsibilities:**
1. Hover coordination (register listeners, dispatch)
2. Parameter type inference (200+ lines)
3. Flow analysis integration
4. Block parameter resolution
5. Method signature formatting
6. Content building coordination

**Metrics:**
- 605 lines (recommended max: 300)
- ~15 public methods
- ~20 private methods
- Multiple concerns mixed

**Impact:**
- Changes risk breaking unrelated features
- Hard to test in isolation
- New contributors struggle to understand

**Solution:**
- [ ] Split into focused classes following SRP:
  ```
  lib/ruby_lsp/type_guessr/hover/
    coordinator.rb           # Main entry point, listener registration
    parameter_inferrer.rb    # Parameter type inference logic
    flow_integration.rb      # FlowAnalyzer integration
    block_param_resolver.rb  # Block parameter type resolution
    signature_formatter.rb   # Method signature formatting
  ```

- [ ] New structure:
  ```ruby
  # coordinator.rb
  class Hover::Coordinator
    def initialize(response_builder, node_context, dispatcher, global_state)
      @response_builder = response_builder
      @node_context = node_context

      # Delegate to specialized resolvers
      @parameter_inferrer = ParameterInferrer.new(node_context, global_state)
      @flow_integration = FlowIntegration.new(node_context)
      @block_resolver = BlockParamResolver.new(node_context, global_state)

      register_listeners(dispatcher)
    end

    def on_required_parameter_node_enter(node)
      # Delegate to parameter_inferrer
      type = @parameter_inferrer.infer_type(node)
      push_content(type) if type
    end
  end

  # parameter_inferrer.rb
  class Hover::ParameterInferrer
    def infer_type(param_node)
      # Extract parameter inference logic (150 lines)
    end
  end

  # Similar for other concerns...
  ```

**Tasks:**
- [ ] Create `lib/ruby_lsp/type_guessr/hover/` directory
- [ ] Extract ParameterInferrer (lines 254-354)
- [ ] Extract FlowIntegration (lines 541-601)
- [ ] Extract BlockParamResolver (lines 476-538)
- [ ] Extract SignatureFormatter (lines 240-249, 403-458)
- [ ] Update tests to work with new structure
- [ ] Ensure backward compatibility

**Benefits:**
- Each class <200 lines
- Clear responsibilities
- Easier to test
- Better code navigation

---

### 8. Hash Incremental Field Addition

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

## 🟡 P2: Quality Improvements

> Code quality and maintainability improvements. Important but can be deferred after P0/P1.

### 10. Test Coverage Gaps

**Problem:** Missing critical test scenarios for production readiness.

**Location:** `spec/` directory

**Why Important:**
- Integration tests too limited (only 1 file)
- No performance regression tests
- No concurrency tests
- Missing real-world scenario tests

**Current Gaps:**

1. **Integration Tests:** Only `spec/integration/hover_spec.rb`
2. **Performance Tests:** None
3. **Concurrency Tests:** None (despite multi-threading)
4. **Real-World Scenarios:** Missing Rails, complex generics, etc.

**Impact:**
- Regressions not caught early
- Performance degradation not detected
- Thread safety issues only found in production
- Edge cases missed

**Solution:**
- [ ] Add comprehensive test suite:
  ```
  spec/
    integration/
      hover_spec.rb                    # ✅ Already exists
      large_project_spec.rb            # NEW: Test with 1000+ files
      concurrent_indexing_spec.rb      # NEW: Parallel AST analysis
      real_rails_project_spec.rb       # NEW: Actual Rails patterns
      incremental_updates_spec.rb      # NEW: File change scenarios

    performance/
      indexing_benchmark_spec.rb       # NEW: Measure indexing speed
      hover_response_spec.rb           # NEW: Hover latency < 100ms
      memory_usage_spec.rb             # NEW: Memory limits respected
      cache_effectiveness_spec.rb      # NEW: Cache hit rates

    concurrency/
      variable_index_spec.rb           # NEW: Concurrent writes
      constant_index_spec.rb           # NEW: Thread safety
      rbs_provider_spec.rb             # NEW: Lazy load race conditions

    scenarios/
      rails_patterns_spec.rb           # NEW: ActiveRecord, helpers
      complex_generics_spec.rb         # NEW: Nested Array[Hash[...]]
      edge_cases_spec.rb               # NEW: Known problematic code
  ```

**Example Tests:**
```ruby
# spec/concurrency/variable_index_spec.rb
RSpec.describe TypeGuessr::Core::VariableIndex do
  it "handles concurrent writes safely" do
    index = described_class.instance
    threads = 10.times.map do |i|
      Thread.new do
        1000.times do |j|
          index.add_method_call(
            file_path: "file_#{i}.rb",
            scope_type: :local_variables,
            scope_id: "method_#{j}",
            var_name: "var_#{j}",
            def_line: j,
            def_column: 0,
            method_name: "foo",
            call_line: j + 1,
            call_column: 0
          )
        end
      end
    end
    threads.each(&:join)

    # Verify no data corruption
    expect(index.size).to eq(10_000)
  end
end

# spec/performance/hover_response_spec.rb
RSpec.describe "Hover performance" do
  it "responds within 100ms for typical method" do
    # Setup: Index a real method
    source = File.read("spec/fixtures/typical_method.rb")
    # ...

    elapsed = Benchmark.realtime do
      # Trigger hover
    end

    expect(elapsed).to be < 0.1  # 100ms
  end
end
```

**Tasks:**
- [ ] Add concurrency tests for all singletons
- [ ] Add performance benchmarks with CI thresholds
- [ ] Add integration tests for large projects
- [ ] Add scenario tests for Rails patterns
- [ ] Set up CI performance regression detection

---

### 11. Variable Name-Based Type Inference

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

### 13. Extended Inference (Operations)

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

### 14. UX Improvements

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

### 15. Replace `__send__` Protected Method Access

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

### 16. Memory Management Strategy (Deferred)

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

### 17. Documentation Improvements

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

### 18. DSL Support

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

### 19. Standalone API

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

### Error Handling Strategy

**Fallback Chain:**

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

**Rules:**

1. **Never crash on hover** - All exceptions caught and logged
2. **Graceful degradation** - Fall back to existing system on any failure
3. **Timeout handling** - Return nil on timeout, don't block LSP
4. **RBS unavailable** - Continue with heuristic inference only
