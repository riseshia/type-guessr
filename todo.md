# TypeGuessr TODO

## Completed

- [x] Optional type formatting (`?Integer` instead of `Integer | nil`)
- [x] Fix doubled activation issue (guard against double activation)
- [x] Inline if/unless support (`x = 1 if condition` → MergeNode with nil)
- [x] Fix IR Dependency Graph visualization (skip body_nodes in traverse to avoid duplicates)

## Future Features

### Array Mutation Tracking

Track type changes when elements are added via mutation methods (`<<`, `push`, `concat`, etc.)

**Options:**
1. **Conservative approach:** Downgrade to `Array[untyped]` when mutation detected
2. **Advanced approach:** Infer argument type and compute union type

**Example:**
```ruby
arr = [1]      # Array[Integer]
arr << "hello" # Array[Integer | String] or Array[untyped]
```

**Challenges:**
- Need to track mutations across method boundaries
- Consider aliasing (`arr2 = arr; arr2 << x`)

### Hash/Array literal internal dependencies

`LiteralNode` currently has empty `dependencies`, so internal values of Hash/Array literals are not tracked in the dependency graph.

**Problem:**
```ruby
result = {
  nodes: @nodes.values,  # Not tracked
  edges: @edges,         # Not tracked
  root_key: node_key     # Not tracked
}
```

Current IR:
```
WriteNode(result)
└── value: LiteralNode(HashShape)
    └── dependencies: []  ← Always empty!
```

**Expected:**
- `@nodes.values` → `CallNode(.values)` → `ReadNode(@nodes)` → `WriteNode(@nodes)`
- `@edges` → `ReadNode(@edges)` → `WriteNode(@edges)`

**Solution options:**
1. Add `HashLiteralNode` with `entries` field for key-value pairs
2. Extend `LiteralNode` with `values` field for internal dependencies
3. Modify `PrismConverter` to track Hash/Array literal contents

### Instance variable ordering limitation

When usage appears before assignment (in method definition order), the type cannot be inferred:

```ruby
class Chef
  def do_something
    @recipe  # Type: unknown (assignment comes later)
  end

  def prepare_recipe
    @recipe = Recipe.new
  end
end
```

**Workaround:** Use accessor methods with memoization.
