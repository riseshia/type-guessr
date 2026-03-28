# T4: Registry Architecture - Ground Truth

## Registry Classes (4 registries + 2 indexes)

### 1. MethodRegistry

**File:** `lib/type_guessr/core/registry/method_registry.rb`
**Class:** `TypeGuessr::Core::Registry::MethodRegistry`
**Stores:** `Hash { "ClassName" => Hash { "method_name" => DefNode } }` + file_path tracking

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | code_index: nil | Creates empty registry, optional code_index for inheritance |
| register | class_name, method_name, def_node, file_path: nil | Store DefNode under class+method, track file_path |
| remove_file | file_path | Remove all entries registered from a specific file |
| lookup | class_name, method_name | Look up DefNode; falls back to ancestor classes via code_index |
| methods_for_class | class_name | Returns Hash of all methods for a class |
| each_entry | &block | Iterate over all (class_name, method_name, def_node) entries |
| source_file_for | class_name, method_name | Returns file_path where method was registered |
| search | pattern | Regex search across all method names, returns matches |
| clear | | Reset all data |

**Resolver usage:**
- `@method_registry.lookup(class_name, method_name)` → get DefNode for project methods
- Used in infer_call (Phase 2 ClassInstance, Phase 3 Unknown Receiver, Phase 4 No Receiver)

### 2. SignatureRegistry

**File:** `lib/type_guessr/core/registry/signature_registry.rb`
**Class:** `TypeGuessr::Core::Registry::SignatureRegistry`
**Stores:** RBS type information via RBSProvider. Contains MethodEntry (RBS-backed) and DslMethodEntry (DSL-registered) inner classes.

**Inner Classes:**
- `MethodEntry`: wraps RBS method_types, provides return_type(arg_types), block_param_types, type_params, block_return_type_var, signatures
- `DslMethodEntry`: simple wrapper with explicit return_type and params, dsl: true flag

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | code_index: nil | Creates with RBSProvider |
| preload | | Preload RBS signatures for common classes |
| preloaded? | | Check if preload completed |
| lookup | class_name, method_name | Returns MethodEntry for instance method (with ancestor fallback) |
| lookup_class_method | class_name, method_name | Returns MethodEntry for class method |
| get_method_return_type | class_name, method_name, arg_types=[] | Returns Type from RBS |
| get_class_method_return_type | class_name, method_name, arg_types=[] | Returns Type from RBS class method |
| get_block_param_types | class_name, method_name | Returns Array<Type> for block params |

**Resolver usage:**
- `@signature_registry.get_method_return_type(...)` → RBS return type fallback
- `@signature_registry.get_block_param_types(...)` → block parameter types for BlockParamSlot
- `@signature_registry.lookup(...)` → get MethodEntry for type_params extraction

### 3. InstanceVariableRegistry

**File:** `lib/type_guessr/core/registry/instance_variable_registry.rb`
**Class:** `TypeGuessr::Core::Registry::InstanceVariableRegistry`
**Stores:** `Hash { "ClassName" => Hash { :@name => WriteNode } }` + file_path tracking

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | code_index: nil | Creates empty registry |
| register | class_name, name, write_node, file_path: nil | Store ivar write node |
| remove_file | file_path | Remove entries from file |
| lookup | class_name, name | Find write node for ivar (with ancestor fallback via code_index) |
| clear | | Reset all data |

**Resolver usage:**
- `@ivar_registry.lookup(class_name, name)` → in infer_instance_variable_read when write_node is nil

### 4. ClassVariableRegistry

**File:** `lib/type_guessr/core/registry/class_variable_registry.rb`
**Class:** `TypeGuessr::Core::Registry::ClassVariableRegistry`
**Stores:** `Hash { "ClassName" => Hash { :@@name => WriteNode } }`

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | | Creates empty registry |
| register | class_name, name, write_node, file_path: nil | Store cvar write node |
| remove_file | file_path | Remove entries from file |
| lookup | class_name, name | Find write node for cvar |
| clear | | Reset all data |

**Resolver usage:**
- `@cvar_registry.lookup(class_name, name)` → in infer_class_variable_read when write_node is nil

### 5. LocationIndex

**File:** `lib/type_guessr/core/index/location_index.rb`
**Class:** `TypeGuessr::Core::Index::LocationIndex`
**Stores:** Nodes indexed by file_path → node_key for fast lookup

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | | Creates empty index |
| add | file_path, node, scope_id="" | Add node to index |
| finalize! | | Finalize after batch indexing |
| find_by_key | node_key | Look up node by key |
| nodes_for_file | file_path | All nodes in a file |
| remove_file | file_path | Remove file's nodes |
| clear | | Reset all data |
| stats | | Statistics hash |
| all_files | | Set of indexed file paths |
| each_node | &block | Iterate all nodes |
| scope_for_node | file_path, node | Find scope_id for a node |

### 6. CodeIndexAdapter

**File:** `lib/ruby_lsp/type_guessr/code_index_adapter.rb`
**Class:** `RubyLsp::TypeGuessr::CodeIndexAdapter`
**Stores:** Wraps ruby-lsp's RubyIndexer::Index; maintains member_index for duck typing

**Public Methods:**
| Method | Parameters | Description |
|--------|-----------|-------------|
| initialize | index | Wraps ruby-lsp index |
| build_member_index! | | Build method→classes mapping for duck typing |
| refresh_member_index! | file_uri | Refresh member_index for a file |
| find_classes_defining_methods | called_methods | Duck typing: find classes having all methods |
| ancestors_of | class_name | Get inheritance chain |
| constant_kind | constant_name | Check if constant is class/module |
| class_method_owner | class_name, method_name | Find owner of class method |
| resolve_constant_name | short_name, nesting | Resolve constant name |
| method_definition_file_path | class_name, method_name, singleton: | Find file where method is defined |
| instance_method_owner | class_name, method_name | Find owner of instance method |
| register_method_class | class_name, method_name | Register DSL-generated method |
| unregister_method_classes | class_name | Remove DSL registrations for class |

## How Registries Work Together

1. **PrismConverter** produces IR nodes and registers them in MethodRegistry, IvarRegistry, CvarRegistry
2. **LocationIndex** stores all nodes for hover/navigation lookup
3. **Resolver** uses registries during inference:
   - First tries MethodRegistry (project code) → DefNode → infer
   - Falls back to SignatureRegistry (RBS stdlib/gem types)
   - IvarRegistry/CvarRegistry for deferred variable resolution
   - CodeIndexAdapter for duck typing (find_classes_defining_methods) and inheritance (ancestors_of)
4. **CodeIndexAdapter** bridges ruby-lsp's index into TypeGuessr's inference pipeline
