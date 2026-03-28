# T6: code_index Usage Map - Ground Truth

## CodeIndexAdapter Class

**File:** `lib/ruby_lsp/type_guessr/code_index_adapter.rb`
**Class:** `RubyLsp::TypeGuessr::CodeIndexAdapter`

Wraps ruby-lsp's `RubyIndexer::Index` and maintains a `member_index` (method→classes mapping) for duck typing.

### Public Methods

| Method | Purpose |
|--------|---------|
| `build_member_index!` | Build method→classes mapping for duck typing |
| `refresh_member_index!(file_uri)` | Refresh member_index for a specific file |
| `member_entries_for_file(file_path)` | Get index entries for a file |
| `find_classes_defining_methods(called_methods)` | Duck typing: find classes that define ALL given methods |
| `ancestors_of(class_name)` | Get inheritance chain (ancestors) |
| `constant_kind(constant_name)` | Check if constant is class/module |
| `class_method_owner(class_name, method_name)` | Find owner of a class method |
| `resolve_constant_name(short_name, nesting)` | Resolve short constant name to FQN |
| `method_definition_file_path(class_name, method_name, singleton:)` | Find file where method is defined |
| `instance_method_owner(class_name, method_name)` | Find owner of an instance method |
| `register_method_class(class_name, method_name)` | Register DSL-generated method in member_index |
| `unregister_method_classes(class_name)` | Remove all DSL registrations for a class |

## Usage Map by File

### 1. Resolver (`lib/type_guessr/core/inference/resolver.rb`)

| Method | Usage | Line |
|--------|-------|------|
| `find_classes_defining_methods(called_methods)` | Duck typing: resolve unknown receiver by finding classes that define all observed methods | ~772 |

Called in `resolve_called_methods` which is used by:
- `infer_call` Phase 3 (unknown receiver)
- `infer_local_read` (unlinked variable)
- `infer_param` (method parameter duck typing)

### 2. MethodRegistry (`lib/type_guessr/core/registry/method_registry.rb`)

| Method | Usage | Line |
|--------|-------|------|
| `ancestors_of(class_name)` | Inheritance fallback in method lookup | ~71 |

When `lookup(class_name, method_name)` doesn't find a direct match, walks ancestors to find inherited methods.

### 3. SignatureRegistry (`lib/type_guessr/core/registry/signature_registry.rb`)

| Method | Usage | Lines |
|--------|-------|-------|
| `ancestors_of(class_name)` | Inheritance fallback for RBS method lookup | ~284 (instance), ~303 (class methods) |

Both `lookup` and `lookup_class_method` walk ancestors to find inherited RBS signatures.

### 4. InstanceVariableRegistry (`lib/type_guessr/core/registry/instance_variable_registry.rb`)

| Method | Usage | Line |
|--------|-------|------|
| `ancestors_of(class_name)` | Inheritance fallback for ivar lookup | ~65 |

When ivar write node not found in class, walks ancestors.

### 5. TypeSimplifier (`lib/type_guessr/core/type_simplifier.rb`)

| Method | Usage | Line |
|--------|-------|------|
| `ancestors_of(type.name)` | Check if one type is ancestor of another for union simplification | ~60 |

Used to simplify `Dog | Animal` → `Animal` when Dog inherits from Animal.

### 6. RuntimeAdapter (`lib/ruby_lsp/type_guessr/runtime_adapter.rb`)

| Method | Usage | Lines |
|--------|-------|-------|
| `build_member_index!` | Initial indexing after all files processed | ~129, ~247 |
| `refresh_member_index!(file_uri)` | Update after file changes | ~141, ~669 |
| `member_entries_for_file(file_path)` | Get entries for DSL processing | ~519 |
| `method_definition_file_path(class_name, method_name, singleton:)` | Find file for method source | ~714 |

### 7. StandaloneRuntime (`lib/type_guessr/mcp/standalone_runtime.rb`)

| Method | Usage | Lines |
|--------|-------|-------|
| `build_member_index!` | Delegate member_index build | ~71 |
| `refresh_member_index!(file_uri)` | Delegate member_index refresh | ~77 |

### 8. ActiveRecordAdapter (`lib/ruby_lsp/type_guessr/dsl/activerecord_adapter.rb`)

| Method | Usage | Lines |
|--------|-------|-------|
| `register_method_class(class_name, method_name)` | Register DSL-generated methods (column readers, associations, etc.) | ~318 |
| `unregister_method_classes(class_name)` | Clean up on schema change | ~146 |

### 9. MCP Server (`lib/type_guessr/mcp/server.rb`)

| Method | Usage | Line |
|--------|-------|------|
| `member_entries_for_file(file_path)` | Get entries for search functionality | ~277 |

## Summary: code_index Method Usage Frequency

| Method | Used By | Count |
|--------|---------|-------|
| `ancestors_of` | MethodRegistry, SignatureRegistry(×2), IvarRegistry, TypeSimplifier | 5 |
| `build_member_index!` | RuntimeAdapter(×2), StandaloneRuntime | 3 |
| `refresh_member_index!` | RuntimeAdapter(×2), StandaloneRuntime | 3 |
| `find_classes_defining_methods` | Resolver | 1 |
| `member_entries_for_file` | RuntimeAdapter, MCP Server | 2 |
| `method_definition_file_path` | RuntimeAdapter | 1 |
| `register_method_class` | ActiveRecordAdapter | 1 |
| `unregister_method_classes` | ActiveRecordAdapter | 1 |
