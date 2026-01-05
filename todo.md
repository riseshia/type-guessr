# TypeGuessr TODO

## In Progress

### Optional type formatting

Display `?Integer` instead of `Integer | nil` for optional types.

**Current:**
```ruby
def find(id)
  @users[id]  # Type: Integer | nil
end
```

**Expected:**
```ruby
def find(id)
  @users[id]  # Type: ?Integer
end
```

## doubled activated

Here is lsp log
```
026-01-05 17:22:44.178 [info] (type-guessr) [TypeGuessr] Ruby LSP indexing completed. Starting TypeGuessr file indexing.

2026-01-05 17:22:44.178 [info] (type-guessr) [TypeGuessr] Ruby LSP indexing completed. Starting TypeGuessr file indexing.
2026-01-05 17:22:44.203 [info] (type-guessr) [TypeGuessr] Found 3548 files to process.

2026-01-05 17:22:44.203 [info] (type-guessr) [TypeGuessr] Found 3548 files to process.
2026-01-05 17:22:44.693 [info] (type-guessr) [TypeGuessr] Indexing progress: 354/3548 (10.0%)

2026-01-05 17:22:44.694 [info] (type-guessr) [TypeGuessr] Indexing progress: 354/3548 (10.0%)
2026-01-05 17:22:45.547 [info] (type-guessr) [TypeGuessr] Indexing progress: 708/3548 (20.0%)

2026-01-05 17:22:45.547 [info] (type-guessr) [TypeGuessr] Indexing progress: 708/3548 (20.0%)
2026-01-05 17:22:46.012 [info] (type-guessr) [TypeGuessr] Indexing progress: 1062/3548 (29.9%)

2026-01-05 17:22:46.012 [info] (type-guessr) [TypeGuessr] Indexing progress: 1062/3548 (29.9%)
2026-01-05 17:22:46.119 [info] (type-guessr) [TypeGuessr] Indexing progress: 1416/3548 (39.9%)

2026-01-05 17:22:46.119 [info] (type-guessr) [TypeGuessr] Indexing progress: 1416/3548 (39.9%)
2026-01-05 17:22:48.413 [info] (type-guessr) [TypeGuessr] Indexing progress: 1770/3548 (49.9%)
```

## inline if / unless support?

looks like it isn't supported. don't need correct type inference, but its ir should build as it means.

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
