# T2: Bug Localization (||= / OrNode) - Ground Truth

## Complete Code Path: Ruby ||= Operator Through TypeGuessr

### 1. Prism Conversion Layer

**File:** `lib/type_guessr/core/converter/prism_converter.rb`

#### Entry Points (Prism AST → IR)

**LocalVariable `x ||= value`:**
- Dispatch (line 192-193): `Prism::LocalVariableOrWriteNode` → `convert_local_variable_or_write()`
- Method (line 522-524): Delegates to `convert_or_write(prism_node, context, :local)`

**InstanceVariable `@var ||= value`:**
- Dispatch (line 201-202): `Prism::InstanceVariableOrWriteNode` → `convert_instance_variable_or_write()`
- Method (line 538-540): Delegates to `convert_or_write(prism_node, context, :instance)`

**IndexOrWrite `hash[:key] ||= value`:**
- Dispatch (line 291): `Prism::IndexOrWriteNode` creates `IR::OrNode(read_call, value_node)` (line 1222)

#### Core: `convert_or_write(prism_node, context, kind)` [PRIVATE] (lines 550-571)

```
1. original_node = lookup_by_kind(name, kind, context)  # look up variable's current node
2. value_node = convert(prism_node.value, context)       # convert RHS
3. or_node = original_node exists ?
     IR::OrNode.new(original_node, value_node, [], loc) :
     value_node                                           # first assignment → just value
4. write_node = create_write_node(name, kind, or_node, ...)
5. register_by_kind(name, write_node, kind, context)
6. return write_node
```

Also handles `||` operator directly:
- `Prism::OrNode` (line 285-286) → `convert_or_node()` (lines 1190-1199)
- Creates `IR::OrNode.new(left_node, right_node, [], loc)`

### 2. IR OrNode Definition

**File:** `lib/type_guessr/core/ir/nodes.rb` (lines 610-648)

```ruby
class OrNode
  attr_reader :lhs, :rhs, :called_methods, :loc

  def initialize(lhs, rhs, called_methods, loc)
    @lhs = lhs              # Left-hand side (original value)
    @rhs = rhs              # Right-hand side (fallback value)
    @called_methods = called_methods
    @loc = loc              # Byte offset
  end

  def dependencies
    [lhs, rhs]              # Both branches need inferring
  end
end
```

### 3. Type Resolution: Resolver#infer_or(node) [PRIVATE]

**File:** `lib/type_guessr/core/inference/resolver.rb` (lines 556-579)

Dispatch: `infer_node` case `IR::OrNode` → `infer_or(node)` (line 133-134)

Logic:
```
1. lhs_result = infer(node.lhs)
2. rhs_result = infer(node.rhs)
3. lhs_type = lhs_result.type

4. If lhs_type is Unknown → return RHS only
   Result.new(rhs_type, "or: rhs_reason (lhs unknown)", rhs_source)

5. truthy_lhs = remove_falsy_types(lhs_type)
   has_falsy = falsy_types?(lhs_type)

6. Three cases:
   a. !has_falsy → LHS always truthy, RHS unreachable
      Result.new(lhs_type, "or: lhs_reason (always truthy)", lhs_source)

   b. truthy_lhs is Unknown → LHS entirely falsy (only nil/false)
      Result.new(rhs_type, "or: rhs_reason (lhs falsy)", rhs_source)

   c. Mixed → truthy part of LHS | RHS (union)
      union = Types::Union.new([truthy_lhs, rhs_type])
      Result.new(union, "or: lhs_reason | rhs_reason", :unknown)
```

### 4. Helper Methods

#### `remove_falsy_types(type)` [PRIVATE] (lines 581-593)
- For Union: filters out NilClass and FalseClass members
  - 0 truthy → Unknown
  - 1 truthy → that single type
  - 2+ truthy → new Union of truthy types
- For non-Union: falsy_type? → Unknown, else → self

#### `falsy_types?(type)` [PRIVATE] (lines 595-602)
- For Union: `type.types.any? { |t| falsy_type?(t) }`
- For non-Union: `falsy_type?(type)`

#### `falsy_type?(type)` [PRIVATE] (lines 604-606)
- `type.is_a?(Types::ClassInstance) && %w[NilClass FalseClass].include?(type.name)`
- Only NilClass and FalseClass are considered falsy in Ruby

### 5. Additional Usage: collect_returns

**File:** `lib/type_guessr/core/converter/prism_converter.rb` (lines 1451-1458)

OrNode is also traversed in `collect_returns`:
```ruby
when IR::OrNode
  returns.concat(collect_returns([node.lhs, node.rhs]))
```

Also used in `infer_narrow` (line 647): `remove_falsy_types` is reused for truthy narrowing in conditionals.

### 6. Complete File Chain

| Step | File | Methods |
|------|------|---------|
| 1. Parse | Prism (external) | Produces `Prism::LocalVariableOrWriteNode` |
| 2. Convert | `converter/prism_converter.rb` | `convert_local_variable_or_write` → `convert_or_write` |
| 3. IR | `ir/nodes.rb` | `OrNode.new(lhs, rhs, called_methods, loc)` |
| 4. Resolve | `inference/resolver.rb` | `infer_node` → `infer_or` |
| 5. Helpers | `inference/resolver.rb` | `remove_falsy_types`, `falsy_types?`, `falsy_type?` |

### 7. Example Trace

**Code:** `x ||= "default"` where x was `String | NilClass`

```
Prism::LocalVariableOrWriteNode
  → convert_or_write(:local)
    → lookup_by_kind(:x, :local) → LocalReadNode (String | NilClass)
    → convert(value) → LiteralNode("default" : String)
    → IR::OrNode(LocalReadNode, LiteralNode)
    → LocalWriteNode(:x, OrNode)

Resolver#infer_or:
  lhs_type = String | NilClass
  rhs_type = String
  truthy_lhs = remove_falsy_types(String | NilClass) = String
  has_falsy = true (NilClass)
  → Mixed case: Union[String, String] → simplifies to String
```
