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

## Instance variable type sharing (Partially Fixed)

Instance variables are now shared across methods within the same class when the assignment comes before usage:

```ruby
class Chef
  def prepare_recipe
    @recipe = Recipe.new  # Assignment first
  end

  def do_something
    @recipe  # Type: Recipe (shared from prepare_recipe)
  end
end
```

**Remaining limitation:** When usage appears before assignment (in method definition order), the type cannot be inferred:

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

**Workaround:** Use accessor methods with memoization:

```ruby
class Chef
  def do_something
    recipe.ingredients
  end

  def recipe
    @recipe ||= Recipe.new  # Type: Recipe
  end
end
```

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
