# TypeGuessr TODO

### Architecture Improvements

#### Node Key Factory
Centralize node key generation in `NodeKeyFactory` class.
- Consistent key format across all node types
- Key parsing for debugging
- Foundation for collision detection

#### SignatureProvider Unified Interface
Create unified method signature lookup with transparent fallback:
1. **Project methods** → User code priority
2. **Bundled gems** → Gem RBS/type info via RubyIndexer
3. **RBS stdlib** → Standard library

Single entry point replaces 5 scattered interfaces:
- `RBSProvider.get_method_signatures`
- `RBSProvider.get_method_return_type`
- `RBSProvider.get_method_return_type_for_args`
- `Resolver.lookup_method`
- `RuntimeAdapter.find_classes_defining_methods`

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

