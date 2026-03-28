# T7: Union Type Method Call Bug - Ground Truth

## Bug Reproduction Path

### Step 1: Variable Assignment
```ruby
x = condition ? [1, 2] : "hello"
```
- PrismConverter creates a MergeNode with two branches:
  - TrueBranch: LiteralNode (TupleType [Integer, Integer])
  - FalseBranch: LiteralNode (ClassInstance "String")
- LocalWriteNode(:x) has value = MergeNode

### Step 2: Method Call
```ruby
x.class
```
- PrismConverter creates CallNode(method: :class, receiver: LocalReadNode(:x))

### Step 3: Type Resolution

#### Resolving `x`
1. `infer(LocalReadNode)` → `infer_local_read` → follows write_node
2. `infer(LocalWriteNode)` → `infer_local_write` → infers value (MergeNode)
3. `infer(MergeNode)` → `infer_merge` → infers both branches → creates `Union([Integer, Integer], String)` which is `Union(TupleType, ClassInstance)`

#### Resolving `x.class`
1. `infer(CallNode)` → `infer_call`
2. receiver is LocalReadNode → infer receiver → gets `Union(TupleType, ClassInstance)`
3. **ROOT CAUSE**: `infer_call`'s case statement (lines ~319-442):
   ```ruby
   case receiver_type
   when Types::SingletonType → ...
   when Types::ClassInstance → ...  (project/RBS lookup)
   when Types::ArrayType → ...
   when Types::TupleType → ...
   when Types::HashShape → ...
   when Types::RangeType → ...
   when Types::HashType → ...
   end
   ```
   **`Types::Union` is not handled.** Falls through the case.
4. Next check: `receiver_type.is_a?(Types::Unknown)` → false (it's Union, not Unknown)
5. Falls to final fallback: `@method_registry.lookup("", "class")` → nil
6. Falls to Object RBS: `@signature_registry.get_method_return_type("Object", "class")` → returns `Class`
7. **Wait**: actually the Object fallback SHOULD work for `.class`... but with `receiver_type` being Union, the `self` substitution won't apply meaningfully.

**Correction on the exact failure path**: For `.class` specifically, the Object RBS fallback at line ~492 would return `Class` (since `Object#class` is defined in RBS). So `.class` might actually work. The real failure manifests for methods NOT on Object:

```ruby
x = condition ? [1, 2] : "hello"
x.length  # Both Array and String have .length, but returns untyped
```

Here `length` would:
1. receiver_type = Union(TupleType, ClassInstance("String"))
2. Not matched in case statement (no Union handler)
3. Not Unknown → duck typing skipped
4. Top-level lookup → nil
5. Object RBS for `length` → Unknown (Object doesn't have `length`)
6. Returns "call length on unknown receiver" → **untyped**

## Root Cause

**File:** `lib/type_guessr/core/inference/resolver.rb`, method `infer_call` (lines ~298-499)

The `case receiver_type` dispatch handles 7 concrete type classes but **does not handle `Types::Union`**. When the receiver is a Union type, no type-specific resolution occurs, and the method falls through to generic fallbacks that only check Object-level RBS.

## Fix Plan

### Approach: Resolve each Union member separately, then union the results

### Files to Modify

#### 1. `lib/type_guessr/core/inference/resolver.rb` [CRITICAL]
**Add Union handling in `infer_call`**, before the Unknown check (~line 443):

```
when Types::Union
  → For each type in union.types:
    → Create a temporary CallNode-like context with that single type as receiver
    → Call infer_call logic for that type
    → Collect results
  → Union all result types
  → Return Result with union type
```

Implementation options:
- **Option A**: Extract a helper `infer_call_on_single_type(receiver_type, node)` and call it for each union member. Simplest but duplicates dispatch logic.
- **Option B**: Recursively call `infer_call` with a synthetic node that has the unwrapped receiver type. Cleaner but needs care with caching.
- **Option C**: Add `when Types::Union` case that iterates `receiver_type.types`, looks up each type's method return type, and unions them. Most direct.

**Recommended: Option C** — minimal code change, follows existing patterns.

Logic:
```ruby
when Types::Union
  result_types = receiver_type.types.filter_map do |member_type|
    # Skip Unknown members
    next if member_type.is_a?(Types::Unknown)

    # Try to resolve method on each member type
    result = resolve_method_on_type(member_type, node)
    result&.type
  end

  if result_types.any?
    union = Types::Union.new(result_types)
    return Result.new(union, "union member dispatch", :stdlib)
  end
```

This requires extracting the per-type resolution logic into a `resolve_method_on_type(type, node)` helper method.

#### 2. `spec/type_guessr/core/inference/resolver_spec.rb` [CRITICAL]
Add test cases:
- Method call on Union(ClassInstance, ClassInstance) → e.g., `(String | Integer).to_s` → String
- Method call on Union(ArrayType, ClassInstance) → e.g., `(Array[Int] | String).length` → Union(Integer, Integer) → Integer
- Method call on Union where one member has the method and another doesn't
- Method call on Union with project methods

#### 3. `lib/type_guessr/core/inference/resolver.rb` — helper extraction [HIGH]
Extract per-type-class dispatch into `resolve_method_on_type(receiver_type, node)`:
- Handles ClassInstance → project/RBS lookup
- Handles ArrayType → Array RBS with substitution
- Handles TupleType → Array RBS fallback
- Handles HashShape/HashType → Hash RBS
- Handles RangeType → Range RBS
- Returns Result or nil

### Files NOT Needing Modification
- `ir/nodes.rb` — no new node types needed
- `types.rb` — Union already exists
- `prism_converter.rb` — MergeNode already produces Union correctly
- `graph_builder.rb` — no change to dependency structure

### Edge Cases to Handle
1. **Empty results**: If no union member defines the method → fall through to Unknown
2. **Mixed sources**: Some members resolve via project, others via RBS → use :unknown source
3. **Recursive unions**: Union(Union(A, B), C) — should be flattened by Union constructor
4. **Performance**: Large unions (cutoff 10) could cause 10× method lookups — acceptable since inference is cached
5. **Self substitution**: Each member needs its own `self` substitution in build_substitutions

## Summary

| Aspect | Detail |
|--------|--------|
| Root cause | `infer_call` case statement missing `Types::Union` handler |
| Affected file | `resolver.rb` (1 file for fix, 1 for tests) |
| Fix complexity | Medium — requires helper extraction + union iteration |
| Risk | Low — Union handling is additive, doesn't change existing paths |
| Test coverage | Need 4-5 new test cases in resolver_spec |
