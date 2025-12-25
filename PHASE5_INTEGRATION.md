# Phase 5: Hover Enhancement - Integration Guide

This document describes the Phase 5 components that have been implemented and how they can be integrated into the existing Hover system.

## Completed Components

All core components for Phase 5 are **fully implemented and tested**:

### 1. TypeFormatter (lib/type_guessr/core/type_formatter.rb)
Converts Type objects to RBS-style strings:
- `Unknown` → `"untyped"`
- `ClassInstance` → class name
- `Union` → `"A | B | C"`
- `ArrayType` → `"Array[ElementType]"`
- `HashShape` → `"{ key: Type, ... }"`

**Status:** ✅ Complete (8 tests passing)

### 2. FlowAnalyzer (lib/type_guessr/core/flow_analyzer.rb)
Performs flow-sensitive type inference for local variables:
- Assignment tracking
- Branch merge (if/else → union)
- Short-circuit operators (||=, &&=)
- Return type inference

**Status:** ✅ Complete (10 tests passing)

### 3. TypeDB (lib/type_guessr/core/type_db.rb)
Storage system for inferred types:
- 2-layer lookup: (file, range) → Type
- File-level invalidation
- Incremental updates

**Status:** ✅ Complete (7 tests passing)

### 4. RBSProvider (lib/type_guessr/core/rbs_provider.rb)
Loads and queries RBS signatures:
- Lazy environment loading
- `get_method_signatures(class_name, method_name)` API
- Handles overloaded signatures

**Status:** ✅ Complete (6 tests passing)

### 5. Core Type System (lib/type_guessr/core/types.rb)
Foundation type representations:
- Unknown, ClassInstance, Union, ArrayType, HashShape
- Type equality and normalization

**Status:** ✅ Complete (31 tests passing)

---

## Integration Approach

### Current Architecture

```
User Hover Request
       ↓
   Hover.rb (LSP Adapter)
       ↓
VariableTypeResolver ──→ VariableIndex (method-call set heuristic)
       ↓
HoverContentBuilder ──→ Display
```

### Target Architecture (Phase 5)

```
User Hover Request
       ↓
   Hover.rb (Enhanced)
       ↓
   ┌───┴───┐
   ↓       ↓
Variable  Method Call/Definition
Hover     Hover (NEW)
   ↓          ↓
TypeDB ←─ FlowAnalyzer    RBSProvider
   ↓          ↓                ↓
TypeFormatter ←───────────────┘
   ↓
Display (RBS-style)
```

### Integration Steps

#### Step 1: Expression Type Hover (5.1)

**Objective:** Use FlowAnalyzer + TypeDB for local variable types

```ruby
# In RuntimeAdapter or similar
def analyze_file(file_path, source)
  analyzer = TypeGuessr::Core::FlowAnalyzer.new
  result = analyzer.analyze(source)

  # Store results in TypeDB
  type_db = TypeGuessr::Core::TypeDB.new
  # ... convert AnalysisResult to TypeDB entries
end

# In Hover
def add_hover_content(node)
  # Try TypeDB first for expression types
  type = type_db.get_type(file_path, node_range)

  if type
    formatted = TypeGuessr::Core::TypeFormatter.format(type)
    @response_builder.push("**Type:** `#{formatted}`")
  else
    # Fallback to existing method-call heuristic
    # ...
  end
end
```

**Changes Required:**
- Add FlowAnalyzer execution in file indexing pipeline
- Store results in TypeDB
- Query TypeDB in Hover before fallback to method-call heuristic

#### Step 2: Call Node Hover (5.2)

**Objective:** Show RBS signatures for method calls

```ruby
# In Hover
def on_call_node_enter(node)
  receiver_type = infer_receiver_type(node.receiver)
  return if receiver_type.nil?

  class_name = extract_class_name(receiver_type)
  method_name = node.name

  rbs_provider = TypeGuessr::Core::RBSProvider.new
  signatures = rbs_provider.get_method_signatures(class_name, method_name)

  if signatures.any?
    content = format_signatures(signatures)
    @response_builder.push(content)
  end
end

def format_signatures(signatures)
  lines = signatures.map { |sig| "  #{sig.method_type}" }
  "**Method signatures:**\n```ruby\n#{lines.join("\n")}\n```"
end
```

**Changes Required:**
- Add `:call` to `HOVER_NODE_TYPES`
- Implement receiver type inference (can use existing VariableTypeResolver)
- Format RBS signatures for display

#### Step 3: Definition Hover (5.3)

**Objective:** Show inferred return type for method definitions

```ruby
# In Hover
def on_def_node_enter(node)
  # Use FlowAnalyzer to get return type
  analyzer = TypeGuessr::Core::FlowAnalyzer.new
  source = extract_method_source(node)
  result = analyzer.analyze(source)

  return_type = result.return_type_for_method(node.name.to_s)
  formatted = TypeGuessr::Core::TypeFormatter.format(return_type)

  @response_builder.push("**Return type:** `#{formatted}`")
end
```

**Changes Required:**
- Add `:def` to `HOVER_NODE_TYPES`
- Extract method source for analysis
- Display inferred return type

---

## Testing Strategy

All core components are fully tested. Integration testing should focus on:

1. **File Indexing Pipeline**
   - FlowAnalyzer execution on file changes
   - TypeDB population and invalidation

2. **Hover Integration**
   - TypeDB lookup for expressions
   - RBSProvider queries for method calls
   - Fallback behavior when types are unknown

3. **Performance**
   - FlowAnalyzer is scope-limited (method/block level)
   - RBSProvider uses lazy loading
   - TypeDB provides fast lookups

---

## Current Status Summary

✅ **Phase 1-4: Complete** (208 tests passing)
- Core Type Model
- TypeDB
- FlowAnalyzer
- RBSProvider
- TypeFormatter

🔄 **Phase 5: Components Ready, Integration Pending**
- All building blocks are implemented and tested
- Integration requires architectural changes to existing Hover system
- Recommended: Incremental integration with feature flags

---

## Recommendation

The core infrastructure for Phase 5 is complete. Full integration should be done incrementally:

1. **First:** Add TypeFormatter to existing type display (low risk)
2. **Second:** Add call node hover with RBSProvider (new feature)
3. **Third:** Integrate FlowAnalyzer + TypeDB (requires file indexing changes)
4. **Fourth:** Add method definition hover (small addition)

Each step can be implemented, tested, and released independently.
