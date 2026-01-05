# TypeGuessr TODO

## Configuration Consolidation

Move all environment variable controls to Config class for consistency.

Currently these environment variables control behavior:
- `TYPE_GUESSR_DEBUG` - Enables debug logging and debug UI features
- `TYPE_GUESSR_DISABLE_DEBUG_SERVER` - Disables the debug web server

These should be configurable through `.type-guessr.yml` as well for better discoverability and consistency.

## Explicit Return Statement Handling

The return type inference doesn't handle explicit `return` statements correctly.

```ruby
def flip(flag = true)
  return false if flag

  flag
end
```

**Expected:** Return type should be `TrueClass | FalseClass` (or `bool`)
**Actual:** Only the last expression (`flag`) is considered

**Proposed Solution:**
- Create a virtual "method return" node that collects all return points
- Track both explicit `return` statements and implicit last-expression returns
- Compute union type from all collected return nodes

## rbs finding fail?

```
raw = File.read("dummy.txt")
```

expected String, but untyped

## Debug Mode Hover Missing Inference Reason

When `TYPE_GUESSR_DEBUG=1` is enabled, the hover UI should show the inference reason/basis, but it's not displaying. Need to investigate the hover provider code path.

## VariableNode Split into WriteNode/ReadNode

Currently `VariableNode` represents both variable assignment (write) and variable reference (read). This causes issues with:

1. **Variable shadowing** - When same variable is reassigned, the dependency chain becomes unclear
2. **Graph visualization** - Hard to distinguish writes from reads visually (partially addressed with `is_read` flag)
3. **Type narrowing** - Difficult to track type changes across reassignments

**Proposed Solution:**
- Split into `WriteNode` (assignment) and `ReadNode` (reference)
- WriteNode depends on the assigned value
- ReadNode depends on the most recent WriteNode for that variable
- Enables cleaner SSA-like representation

## Inference Bug: Conditional String Building

```ruby
def build_debug_info(result, ir_node = nil)
  info = "\n\n**[TypeGuessr Debug]**"
  info += "\n\n**Reason:** #{result.reason}"
  if ir_node
    called_methods = extract_called_methods(ir_node)
    info += "\n\n**Method calls:** #{called_methods.join(", ")}" if called_methods.any?
  end
  info
end
```

The `info` variable's type should be `String` throughout, but inference may be failing due to:
- Multiple reassignments via `+=`
- Conditional modification inside `if` block
- Need to investigate specific failure mode

## Debug Graph: CallNode Subgraph Internal Edges

When a CallNode is rendered as a subgraph (because it has arguments), the argument nodes inside the subgraph still show edges pointing to the subgraph itself.

**Example:** `foo(bar)` becomes subgraph, but `bar` node shows edge to `foo` subgraph which is redundant since `bar` is already inside the subgraph.

**Proposed Fix:**
- Skip rendering edges where the target is the parent subgraph
- Or render these edges differently (dotted line, different color)

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

### Hash Shape Inference Enhancement

Improve `HashShape` inference for dynamically constructed hashes:

```ruby
result = {}
result[:name] = user.name
result[:email] = user.email
# Should infer: { name: String, email: String }
```

### Block Return Type Inference

Better inference for block return types in methods like `map`, `select`, etc.:

```ruby
users.map { |u| u.name }  # Should infer Array[String] if User#name -> String
```

### Method Signature Caching

Cache inferred method signatures to avoid re-computation on every hover/request.

### Cross-file Type Propagation

Track type information across file boundaries for better inference in multi-file projects.
