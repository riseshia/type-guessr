# T1: CallNode Type Resolution Chain - Ground Truth

## Complete Chain: CallNode Type Resolution

### 1. Entry Point: `Resolver#infer(node)` [PUBLIC]

**File:** `lib/type_guessr/core/inference/resolver.rb`

Guard checks (early returns):
1. `node.nil?` → `Result.new(Types::Unknown.instance, "no node", :unknown)`
2. `@cache[node] == INFERRING` → `Result.new(Types::Unknown.instance, "circular reference", :unknown)`
3. `@cache[node]` exists → return cached Result
4. `@depth >= MAX_DEPTH (50)` → `Result.new(Types::Unknown.instance, "max depth exceeded", :unknown)`

Then sets `@cache[node] = INFERRING` sentinel, increments depth, calls `infer_node(node)`, decrements depth, applies type simplification if available, caches and returns result.

### 2. Dispatcher: `Resolver#infer_node(node)` [PRIVATE]

Case statement dispatching by node type. For `IR::CallNode` → calls `infer_call(node)`.

Complete dispatch table: LiteralNode→infer_literal, LocalWriteNode→infer_local_write, LocalReadNode→infer_local_read, InstanceVariableWriteNode→infer_instance_variable_write, InstanceVariableReadNode→infer_instance_variable_read, ClassVariableWriteNode→infer_class_variable_write, ClassVariableReadNode→infer_class_variable_read, ParamNode→infer_param, ConstantNode→infer_constant, CallNode→infer_call, BlockParamSlot→infer_block_param_slot, OrNode→infer_or, MergeNode→infer_merge, DefNode→infer_def, SelfNode→infer_self, NarrowNode→infer_narrow, ReturnNode→infer_return.

### 3. Main Method: `Resolver#infer_call(node)` [PRIVATE]

#### Phase 1: Constant Receiver
If `node.receiver.is_a?(IR::ConstantNode)`:
- Infer receiver → extract class_name from SingletonType or constant node name
- Delegate to `infer_class_method_call(class_name, node)`
- Return early if resolved

#### Phase 2: Dynamic Receiver - Type Cases
Infer receiver type, then case on receiver_type:

**SingletonType:** Delegate to `infer_class_method_call(name, node)`

**ClassInstance:**
1. Try project methods: `@method_registry.lookup(name, method)` → infer DefNode → Result(:project)
2. Fall back to RBS: `@signature_registry.get_method_return_type(name, method, arg_types)` (with Object fallback)
3. Type variable substitution: `build_substitutions` + `add_method_type_var_substitutions` + `return_type.substitute`
4. Return Result(:stdlib)

**ArrayType:** Build substitutions {Elem→element_type, self→receiver}, get Array RBS signature, substitute, return Result(:stdlib)

**TupleType:** Special case for `[]` with integer literal → `infer_tuple_access`. Otherwise fall back to Array RBS.

**HashShape:** Special case for `[]` with symbol literal → `infer_hash_shape_access`. Otherwise fall back to Hash RBS.

**RangeType:** Substitutions {Elem→element_type, self→receiver}, Range RBS, substitute.

**HashType:** Substitutions {K→key_type, V→value_type, self→receiver}, Hash RBS, substitute.

#### Phase 3: Unknown Receiver
If receiver_type is Unknown:
- Create CalledMethod(name: method, positional_count: nil, keywords: [])
- `resolve_called_methods([cm])` → uses code_index to find classes defining the method
- If ClassInstance found: try project methods then RBS with inferred receiver
- Return with "(inferred receiver)" reason

#### Phase 4: No Receiver
- Try top-level method: `@method_registry.lookup("", method)` → Result(:project)
- Fall back to Object RBS
- Final fallback: Result(Unknown, "call method on unknown receiver", :unknown)

### 4. Helper Methods

#### `infer_class_method_call(class_name, node)` [PRIVATE]
- `.new` → always returns `ClassInstance.for(class_name)` with source :inference
- Try project class methods via `@code_index.class_method_owner` → `@method_registry.lookup` → infer DefNode → Result(:project)
- Fall back to RBS: `@signature_registry.get_class_method_return_type` → Result(:rbs)
- Returns nil if not resolved (caller tries other strategies)

#### `infer_hash_shape_access(hash_shape, key_node)` [PRIVATE]
- Guards: key_node must be LiteralNode, Symbol type, Symbol literal_value
- Returns field type if found in hash_shape.fields
- Returns NilClass for missing fields

#### `infer_tuple_access(tuple_type, index_node)` [PRIVATE]
- Guards: index_node must be LiteralNode, Integer type, Integer literal_value
- Supports negative indexing
- Returns element type at position, NilClass for out-of-range

#### `resolve_called_methods(called_methods)` [PRIVATE]
- Returns Unknown if empty
- Uses `@code_index.find_classes_defining_methods(called_methods)` → `classes_to_type`

#### `build_substitutions(receiver_type)` [PRIVATE]
- Gets type_variable_substitutions from receiver + adds `:self` → receiver_type

#### `add_method_type_var_substitutions(...)` [PRIVATE]
- Looks up MethodEntry in signature_registry (with Object fallback)
- Adds block return type var + remaining type params (substituted with Unknown)

### 5. Result Class

**File:** `lib/type_guessr/core/inference/result.rb`

Attributes: `type` (Types::Type), `reason` (String), `source` (Symbol: :literal, :project, :stdlib, :rbs, :gem, :inference, :unknown)

### 6. CallNode Structure

**File:** `lib/type_guessr/core/ir/nodes.rb`

Attributes: `method` (Symbol), `receiver` (Node|nil), `args` (Array<Node>), `block_params` (Array<Symbol>), `block_body` (Node|nil), `has_block` (Boolean), `called_methods` (Array<CalledMethod>), `loc` (Integer)

Dependencies: [receiver] + args + [block_body]
