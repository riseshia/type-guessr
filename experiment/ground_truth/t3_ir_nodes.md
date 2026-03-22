# T3: IR Node Catalog - Ground Truth

**File:** `lib/type_guessr/core/ir/nodes.rb`

## Support Types

### CalledMethod (Data.define)
- Fields: name (Symbol), positional_count (Integer|nil), keywords (Array<Symbol>)
- Used for duck typing inference

## Node Classes (17 total)

### 1. LiteralNode (lines ~113-148)
- **Attributes:** type, literal_value, values, called_methods, loc
- **Dependencies:** `values || []` (internal value nodes for compound literals)
- **Purpose:** Represents literal values (strings, integers, arrays, hashes, symbols, etc.)

### 2. LocalWriteNode (lines ~157-188)
- **Attributes:** name, value, called_methods, loc
- **Dependencies:** `value ? [value] : []`
- **Purpose:** Local variable assignment (e.g., `x = expr`)

### 3. LocalReadNode (lines ~197-228)
- **Attributes:** name, write_node, called_methods, loc
- **Dependencies:** `write_node ? [write_node] : []`
- **Purpose:** Local variable reference. called_methods is shared with its WriteNode.

### 4. InstanceVariableWriteNode (lines ~236-269)
- **Attributes:** name, class_name, value, called_methods, loc
- **Dependencies:** `value ? [value] : []`
- **Purpose:** Instance variable assignment (`@x = expr`)

### 5. InstanceVariableReadNode (lines ~280-313)
- **Attributes:** name, class_name, write_node, called_methods, loc
- **Dependencies:** `write_node ? [write_node] : []`
- **Purpose:** Instance variable read. write_node may be nil (deferred resolution via class_name).

### 6. ClassVariableWriteNode (lines ~321-354)
- **Attributes:** name, class_name, value, called_methods, loc
- **Dependencies:** `value ? [value] : []`
- **Purpose:** Class variable assignment (`@@x = expr`)

### 7. ClassVariableReadNode (lines ~362-395)
- **Attributes:** name, class_name, write_node, called_methods, loc
- **Dependencies:** `write_node ? [write_node] : []`
- **Purpose:** Class variable read. Similar deferred resolution pattern as ivar.

### 8. ParamNode (lines ~406-439)
- **Attributes:** name, kind, default_value, called_methods, loc
- **Dependencies:** `default_value ? [default_value] : []`
- **Purpose:** Method parameter. kind is one of: :required, :optional, :rest, :keyword_required, :keyword_optional, :keyword_rest, :block, :forwarding

### 9. ConstantNode (lines ~446-477)
- **Attributes:** name, dependency, called_methods, loc
- **Dependencies:** `dependency ? [dependency] : []`
- **Purpose:** Constant reference (e.g., `User`, `Admin::User`)

### 10. CallNode (lines ~488-532)
- **Attributes:** method, receiver, args, block_params (accessor), block_body (accessor), has_block (accessor), called_methods, loc
- **Dependencies:** `[receiver] + args + [block_body]` (filtered for nil)
- **Purpose:** Method call. Most complex node. block_params/block_body/has_block are mutable (set after construction).

### 11. BlockParamSlot (lines ~540-571)
- **Attributes:** index, call_node, called_methods, loc
- **Dependencies:** `[call_node]`
- **Purpose:** Block parameter (e.g., `|user|` in `users.each { |user| }`). Shares called_methods with associated variable.

### 12. MergeNode (lines ~579-608)
- **Attributes:** branches, called_methods, loc
- **Dependencies:** `branches` (Array<Node>)
- **Purpose:** Branch convergence (if/else, case/when). Type is union of all branch types.

### 13. OrNode (lines ~617-648)
- **Attributes:** lhs, rhs, called_methods, loc
- **Dependencies:** `[lhs, rhs]`
- **Purpose:** Short-circuit || and ||= operations. Removes falsy types from LHS.

### 14. DefNode (lines ~659-704)
- **Attributes:** name, class_name, params, return_node, body_nodes, called_methods, loc, singleton, module_function
- **Dependencies:** `params + [return_node] + body_nodes` (filtered for nil)
- **Purpose:** Method definition. Container for params and return node.

### 15. ClassModuleNode (lines ~711-742)
- **Attributes:** name, methods, called_methods, loc
- **Dependencies:** `methods` (Array<DefNode>)
- **Purpose:** Class/module container for method definitions.

### 16. SelfNode (lines ~749-780)
- **Attributes:** class_name, singleton, called_methods, loc
- **Dependencies:** `[]` (none)
- **Purpose:** Self reference. Returns ClassInstance or SingletonType based on singleton flag.

### 17. NarrowNode (lines ~789-820)
- **Attributes:** value, kind, called_methods, loc
- **Dependencies:** `value ? [value] : []`
- **Purpose:** Type narrowing after guard clauses. kind :truthy removes nil/false.

### 18. ReturnNode (lines ~826-855)
- **Attributes:** value, called_methods, loc
- **Dependencies:** `value ? [value] : []`
- **Purpose:** Explicit `return` statement.

## Common Patterns

- All nodes include TreeInspect mixin for pretty-printing
- All nodes have `called_methods` and `loc` fields
- All nodes implement `dependencies`, `node_hash`, `node_key(scope_id)`
- Dependencies form a reverse dependency graph for topological resolution
- called_methods arrays are often shared between related nodes (Write/Read pairs)
