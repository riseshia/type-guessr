# Phase 5: Hover Enhancement - Design Document

## Overview

This document describes the design for integrating type inference components (implemented in Phase 1-4) into the existing Hover system.

**Key Question**: Do the new components replace or augment the existing system?

**Conclusion**: **Augmentation** - New components serve as fallbacks to the existing method-call heuristic, gradually becoming the primary source over time.

---

## 1. Implemented Components Summary

| Component | Role | Tests | Dependencies |
|-----------|------|-------|--------------|
| `Types` | Type representation (Unknown, Union, etc.) | 31 | None |
| `TypeDB` | (file, range) → Type storage | 7 | Types |
| `FlowAnalyzer` | Flow-sensitive local variable analysis | 10 | Types, Prism |
| `RBSProvider` | RBS signature lookup | 6 | RBS gem |
| `TypeFormatter` | Type → RBS-style string | 8 | Types |

---

## 2. Current vs Target Architecture

### 2.1 Current System

```
[Hover Request]
      │
      ▼
┌─────────────────┐
│     Hover.rb    │ ← LSP event listener
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  VariableTypeResolver   │ ← Extract variable info from node
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│    VariableIndex        │ ← method-call set storage (existing)
│  + TypeMatcher          │ ← method-call set → candidate types
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│  HoverContentBuilder    │ ← Format results
└─────────────────────────┘
```

**Current Limitations**:
- Only method-call heuristic → no inference without method calls
- Only literal assignments recognized as direct_type
- RBS information not utilized

### 2.2 Target System

```
[Hover Request]
      │
      ▼
┌─────────────────────────────────────────────────────┐
│                    Hover.rb                          │
│  ┌─────────────┬─────────────┬────────────────────┐ │
│  │ Variable    │ Call Node   │ Def Node           │ │
│  │ Hover       │ Hover (NEW) │ Hover (NEW)        │ │
│  └──────┬──────┴──────┬──────┴─────────┬──────────┘ │
└─────────┼─────────────┼────────────────┼────────────┘
          │             │                │
          ▼             ▼                ▼
    ┌───────────┐  ┌───────────┐  ┌───────────────┐
    │  TypeDB   │  │RBSProvider│  │ FlowAnalyzer  │
    │(1st try)  │  │           │  │ (on-demand)   │
    └─────┬─────┘  └───────────┘  └───────────────┘
          │
          ▼ (fallback)
    ┌─────────────────────────┐
    │ VariableIndex (existing)│
    │ + TypeMatcher           │
    └─────────────────────────┘
          │
          ▼
    ┌─────────────────────────┐
    │    TypeFormatter        │ ← Unified output formatting
    └─────────────────────────┘
```

---

## 3. Key Design Decisions

### 3.1 FlowAnalyzer Execution Timing

**Option A: At file indexing time (Background)**
- Pros: Fast hover response
- Cons: Increased memory usage, complex invalidation logic

**Option B: At hover request time (On-demand)**
- Pros: Always up-to-date results, simple implementation
- Cons: Possible hover response delay (mitigated by scope-limited analysis)

**Decision: Option B (On-demand) with caching**
- FlowAnalyzer only analyzes method/block scope → fast
- Results reused for repeated requests on same file

### 3.2 RBSProvider Instance Management

**Decision: Singleton with lazy loading**
```ruby
# RBS environment loading is heavy (~500ms)
# Load only on first request, reuse thereafter
module TypeGuessr::Core
  class RBSProvider
    class << self
      def instance
        @instance ||= new
      end
    end
  end
end
```

### 3.3 Type Inference Priority

```
1. TypeDB (FlowAnalyzer results) ← Most accurate
2. VariableIndex direct_type    ← Literal/.new assignments
3. TypeMatcher (method-call)    ← Heuristic fallback
4. Unknown                      ← Final fallback
```

### 3.4 Compatibility with Existing System

**No Changes**:
- VariableIndex, TypeMatcher, VariableTypeResolver remain unchanged
- All existing tests continue to pass

**Extensions**:
- Integrate TypeFormatter into HoverContentBuilder
- Add new node type listeners to Hover (call, def)

---

## 4. Integration Details

### Phase 5.1: TypeFormatter Integration (Low Risk)

**Files to Change**: `hover_content_builder.rb`

**Current**:
```ruby
"**Guessed type:** `#{type_name}`"
```

**After**:
```ruby
# If type_name is String, use existing approach
# If Type object, use TypeFormatter
formatted = type_name.is_a?(String) ? type_name : TypeFormatter.format(type_name)
"**Guessed type:** `#{formatted}`"
```

**Impact**: Output format change only, no logic changes

---

### Phase 5.2: Call Node Hover (Medium Risk)

**Files to Change**: `hover.rb`

**Additions**:
```ruby
HOVER_NODE_TYPES = [
  # ... existing items ...
  :call,  # NEW
].freeze

def on_call_node_enter(node)
  # 1. Infer receiver type
  receiver_type = resolve_receiver_type(node.receiver)
  return if receiver_type.nil? || receiver_type == "Unknown"

  # 2. Query RBS signatures
  signatures = RBSProvider.instance.get_method_signatures(
    receiver_type,
    node.name.to_s
  )
  return if signatures.empty?

  # 3. Format and output
  content = format_method_signatures(node.name, signatures)
  @response_builder.push(content, category: :documentation)
end
```

**Dependencies**: Uses existing VariableTypeResolver for receiver type inference

**Risk**: RBS loading delay (mitigated by lazy loading)

---

### Phase 5.3: FlowAnalyzer Integration (High Risk)

**Files to Change**: `hover.rb`, `variable_type_resolver.rb`

**Approach**: Add parallel path without modifying VariableTypeResolver

```ruby
# In Hover
def add_hover_content(node)
  # 1. Try FlowAnalyzer (new path)
  flow_type = try_flow_analysis(node)
  if flow_type && flow_type != Types::Unknown.instance
    formatted = TypeFormatter.format(flow_type)
    @response_builder.push("**Type:** `#{formatted}`", category: :documentation)
    return
  end

  # 2. Existing path (fallback)
  type_info = @type_resolver.resolve_type(node)
  # ... existing logic ...
end

private

def try_flow_analysis(node)
  # Scope-limited analysis: current method/block only
  source = extract_containing_scope_source(node)
  return nil if source.nil?

  analyzer = FlowAnalyzer.new
  result = analyzer.analyze(source)
  result.type_at(node.location.start_line, node.location.start_column)
rescue => e
  nil  # Fallback on failure
end
```

**Risks**:
- Scope extraction logic complexity
- Performance impact (mitigated by scope-limiting)

---

### Phase 5.4: Definition Hover (Low Risk)

**Additions**:
```ruby
HOVER_NODE_TYPES = [
  # ...
  :def,  # NEW
].freeze

def on_def_node_enter(node)
  # Use FlowAnalyzer for return type inference
  source = node.slice  # method body only
  analyzer = FlowAnalyzer.new
  result = analyzer.analyze("def #{node.name}\n#{source}\nend")

  return_type = result.return_type_for_method(node.name.to_s)
  formatted = TypeFormatter.format(return_type)

  @response_builder.push(
    "**Return type:** `#{formatted}`",
    category: :documentation
  )
end
```

---

## 5. Performance Considerations

### LSP Response Time Constraints
- Target: < 100ms (hover response)
- RBS first load: ~500ms → solved with lazy loading + singleton
- FlowAnalyzer: scope-limited → typically < 10ms

### Memory
- RBS Environment: ~50MB (loaded once)
- TypeDB: few KB per file (if implemented)
- FlowAnalyzer: one-time analysis, no caching needed

---

## 6. Implementation Priority and Rationale

| Order | Task | Risk | Value | Rationale |
|-------|------|------|-------|-----------|
| 1 | TypeFormatter integration | Low | Medium | Minimal code changes, improved output |
| 2 | Call Node Hover | Medium | High | New feature, immediate RBSProvider use |
| 3 | Def Node Hover | Low | Medium | Uses FlowAnalyzer, independent |
| 4 | FlowAnalyzer integration | High | High | Most complex, interacts with existing system |

**Rationale**:
- 1, 2, 3 can be implemented/deployed independently
- 4 requires understanding of existing system, do last

---

## 7. Testing Strategy

### Unit Tests (Existing)
- All component tests complete (208 tests)

### Integration Tests (To Be Added)

```ruby
# Call Node Hover
describe "call node hover" do
  it "shows RBS signature for String#upcase" do
    source = 'str = "hello"; str.upcase'
    response = hover_at(source, line: 0, char: 18)  # 'upcase' position
    expect(response).to include("() -> String")
  end
end

# Def Node Hover
describe "def node hover" do
  it "shows inferred return type" do
    source = "def foo; 42; end"
    response = hover_at(source, line: 0, char: 4)  # 'foo' position
    expect(response).to include("Integer")
  end
end
```

---

## 8. Conclusion

All Phase 5 building blocks are fully implemented. Integration follows these principles:

1. **Preserve Existing System**: Augment, don't replace
2. **Incremental Integration**: Separate into independently deployable units
3. **Guaranteed Fallback**: Maintain existing behavior when new features fail
4. **Performance First**: Lazy loading, scope-limited analysis

Estimated effort:
- Phase 5.1 (TypeFormatter): ~1 hour
- Phase 5.2 (Call Hover): ~2 hours
- Phase 5.3 (Def Hover): ~1 hour
- Phase 5.4 (FlowAnalyzer): ~4 hours
