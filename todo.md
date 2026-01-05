# TypeGuessr TODO

## Completed

- [x] Optional type formatting (`?Integer` instead of `Integer | nil`)
- [x] Fix doubled activation issue (guard against double activation)
- [x] Inline if/unless support (`x = 1 if condition` → MergeNode with nil)

## IR Dependency Graph seems strange

Check `GraphBuilder.build`. for instance, there is two return node with nil. it has 3 graphs, but it should be one directed graph.

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
