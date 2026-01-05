# TypeGuessr TODO

## Restore TypeInferrer Integration

The custom TypeInferrer swap mechanism was removed during Phase 4 & 5 rewrite (commit 006e7c8).

**Original Implementation (removed):**
- `lib/ruby_lsp/type_guessr/type_inferrer.rb` - Custom TypeInferrer
- Swapped ruby-lsp's TypeInferrer to enhance Go to Definition with inferred types
- Related commits: 9e2ec9c, 749626b, e7ebc46, 8150e27

**Why Restore:**
- Go to Definition currently doesn't benefit from TypeGuessr's type inference
- The original goal was to enhance ruby-lsp's navigation features with heuristic types

**Implementation Plan:**
- Review the old implementation from git history
- Adapt to current IR-based architecture
- Hook into ruby-lsp's TypeInferrer to provide inferred types for Go to Definition

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

## Refactor integration hover spec

- always use `let(:source)` even test is not doc test attaged
- `Guessed Type` matching should use `expect_hover_type`\

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
