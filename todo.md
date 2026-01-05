# TypeGuessr TODO

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

## member var doesn't share its types

```
class Chef
  def do
    @recipe.ingredients
  end

  def prepare_recipe
    @recipe = Recipe.new
  end
end
```

@recipe expected `?Recipe` all over the place

```
class Chef
  def do
    recipe.ingredients
  end

  def recipe
    @recipe ||= Recipe.new
  end
end
```

it's better to be guessed `Chef#recipe` as `() -> Recipe`.

## Optional type

expected ?Integer
actual Integer | nil

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
