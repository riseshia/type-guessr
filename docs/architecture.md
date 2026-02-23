# TypeGuessr Architecture

## Overview

TypeGuessr is a Ruby LSP addon that provides heuristic type inference without requiring explicit type annotations. It converts Prism AST nodes into a graph structure optimized for type inference.

## Architecture Layers

```
┌───────────────────────────────────────────────────────────────────────────────┐
│                           Ruby LSP Integration                                 │
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐  ┌─────────────────────────┐ │
│  │   Addon   │  │   Hover   │  │ RuntimeAdapter│  │     TypeInferrer        │ │
│  │           │  │           │  │               │  │                         │ │
│  │ - activate│  │ - hover   │  │ - index mgmt  │  │ - ruby-lsp integration  │ │
│  │ - file    │  │ - type    │  │ - inference   │  │ - type coordination     │ │
│  │   watch   │  │   display │  │ - mutex sync  │  │                         │ │
│  └───────────┘  └───────────┘  └───────────────┘  └─────────────────────────┘ │
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐  ┌─────────────────────────┐ │
│  │  Config   │  │DebugServer│  │ GraphBuilder  │  │    CodeIndexAdapter     │ │
│  │           │  │           │  │               │  │                         │ │
│  │ - yaml    │  │ - http    │  │ - node graph  │  │ - RubyIndexer wrapper   │ │
│  │ - env     │  │ - inspect │  │ - prism coord │  │ - duck type search      │ │
│  └───────────┘  └───────────┘  └───────────────┘  └─────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                                 Core Layer                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ PrismConverter│  │  RBSConverter │  │ LocationIndex │  │   Resolver    │   │
│  │               │  │               │  │               │  │               │   │
│  │ Prism AST→IR  │  │ RBS→Types     │  │ node_key      │  │ IR Node→Type  │   │
│  │               │  │               │  │  → IR Node    │  │               │   │
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘   │
│                                                                                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────────────────┐   │
│  │   IR Nodes    │  │    Types      │  │      SignatureRegistry            │   │
│  │               │  │               │  │                                   │   │
│  │ - LiteralNode │  │ - ClassInst   │  │ - preload stdlib RBS              │   │
│  │ - Local*Node  │  │ - ArrayType   │  │ - O(1) method lookup              │   │
│  │ - IVar*Node   │  │ - TupleType   │  │ - overload resolution             │   │
│  │ - CVar*Node   │  │ - HashType    │  │ - block param types               │   │
│  │ - CallNode    │  │ - HashShape   │  │                                   │   │
│  │ - ParamNode   │  │ - RangeType   │  │                                   │   │
│  │ - DefNode     │  │ - Union       │  │                                   │   │
│  │ - MergeNode   │  │ - Singleton   │  │                                   │   │
│  │ - OrNode      │  │ - MethodSig   │  │                                   │   │
│  │ - SelfNode    │  │ - TypeVar     │  │                                   │   │
│  │ - ReturnNode  │  │ - Unguessed   │  │                                   │   │
│  │ - NarrowNode  │  │               │  │                                   │   │
│  └───────────────┘  └───────────────┘  └───────────────────────────────────┘   │
│                                                                                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │TypeSimplifier │  │    Logger     │  │MethodRegistry │  │IVarRegistry   │   │
│  │               │  │               │  │               │  │CVarRegistry   │   │
│  │ - union simp  │  │ - debug log   │  │ - register    │  │               │   │
│  │ - normalize   │  │               │  │ - lookup      │  │ - ivar store  │   │
│  │               │  │               │  │ - inheritance │  │ - cvar store  │   │
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘   │
└───────────────────────────────────────────────────────────────────────────────┘
```

## Core Components

### Nodes (`lib/type_guessr/core/ir/nodes.rb`)

Nodes form a reverse dependency graph where each node points to the nodes it depends on for type inference.

| Node Type | Purpose | Dependency |
|-----------|---------|------------|
| `LiteralNode` | Literals (string, integer, array, hash) | None (leaf node) |
| `LocalWriteNode` | Local variable assignment | Points to assigned value node |
| `LocalReadNode` | Local variable reference | Points to LocalWriteNode |
| `InstanceVariableWriteNode` | Instance variable assignment (@var =) | Points to assigned value node |
| `InstanceVariableReadNode` | Instance variable reference (@var) | Points to InstanceVariableWriteNode |
| `ClassVariableWriteNode` | Class variable assignment (@@var =) | Points to assigned value node |
| `ClassVariableReadNode` | Class variable reference (@@var) | Points to ClassVariableWriteNode |
| `ParamNode` | Method parameters | Points to default value (called_methods tracked for inference) |
| `CallNode` | Method calls | Points to receiver + args |
| `DefNode` | Method definitions | Points to body (return value) |
| `BlockParamSlot` | Block parameters | Filled by CallNode inference |
| `MergeNode` | Control flow merge (if/else) | Points to all branches |
| `OrNode` | Compound assignment (||=) | Points to left and right value nodes |
| `ConstantNode` | Constants | Points to assigned value |
| `ClassModuleNode` | Class/module definitions | Contains method DefNodes |
| `SelfNode` | Self reference | None (resolved from class context) |
| `ReturnNode` | Explicit return statement | Points to return value node |
| `NarrowNode` | Type narrowing after guard clauses | Points to value node (removes falsy types) |

### PrismConverter (`lib/type_guessr/core/converter/prism_converter.rb`)

Converts Prism AST to node graph at indexing time.

**Key responsibilities:**
- Convert Prism nodes to IR nodes
- Track variable definitions via Context
- Handle method calls and track called methods on variables
- Handle indexed assignment (`a[:key] = value`) for Hash type tracking
- Handle multiple assignment (`a, b = expr`) via synthetic `[]` calls
- Handle compound assignments (`||=`, `&&=`, `+=`)

**Context:**
- Maintains variable → IR node mapping within a scope
- Enables variable reassignment tracking
- Handles Hash indexed assignment type updates
- Accepts injected registries (LocationIndex, MethodRegistry, variable registries) for inline node registration

### RBSConverter (`lib/type_guessr/core/converter/rbs_converter.rb`)

Converts RBS types to internal type system.

**Key responsibilities:**
- Parse RBS type syntax
- Convert to TypeGuessr::Core::Types representations
- Isolate RBS dependencies from core inference logic

### LocationIndex (`lib/type_guessr/core/index/location_index.rb`)

O(1) lookup from node key to node.

**Key features:**
- Hash-based O(1) lookup using `node_key` (generated by `NodeKeyGenerator`)
- Per-file key tracking for efficient `remove_file` cleanup
- `find_by_key(node_key)` - primary lookup method
- `nodes_for_file(file_path)` - get all nodes for a file

### Resolver (`lib/type_guessr/core/inference/resolver.rb`)

Resolves nodes to types by traversing the dependency graph.

**Key features:**
- Caches inference results per node
- Handles RBS method signature lookup
- Resolves block parameter types from receiver's element type
- Method-based type inference via called method resolution
- Uses injected `MethodRegistry`, `InstanceVariableRegistry`, and `ClassVariableRegistry` for storage

### MethodRegistry (`lib/type_guessr/core/registry/method_registry.rb`)

Stores and retrieves project method definitions (DefNode).

**Key features:**
- `register(class_name, method_name, def_node)` - Store method definition
- `lookup(class_name, method_name)` - Find method (supports inheritance via code_index)
- `methods_for_class(class_name)` - Get direct methods for a class (debug server)
- `search(pattern)` - Search methods by pattern (debug server)

### InstanceVariableRegistry (`lib/type_guessr/core/registry/instance_variable_registry.rb`)

Stores and retrieves instance variable definitions.

**Key features:**
- `register(class_name, name, write_node)` - Store instance variable
- `lookup(class_name, name)` - Find instance variable (supports inheritance via code_index)

### ClassVariableRegistry (`lib/type_guessr/core/registry/class_variable_registry.rb`)

Stores and retrieves class variable definitions.

**Key features:**
- `register(class_name, name, write_node)` - Store class variable
- `lookup(class_name, name)` - Find class variable

### Types (`lib/type_guessr/core/types.rb`)

Type representations:

| Type | Example | Description |
|------|---------|-------------|
| `ClassInstance` | `String`, `Integer` | Single class type |
| `SingletonType` | `singleton(User)` | Class object itself (singleton class) |
| `ArrayType` | `Array[Integer]` | Array with element type |
| `TupleType` | `[Integer, String]` | Array with per-position types (max 8 elements) |
| `HashType` | `Hash[Symbol, String]` | Hash with key/value types |
| `HashShape` | `{ a: Integer, b: String }` | Hash with known fields |
| `RangeType` | `Range[Integer]` | Range with element type |
| `Union` | `Integer \| String` | Union of types |
| `Unknown` | `untyped` | Unknown type (singleton) |
| `Unguessed` | `unguessed` | Type exists but not yet inferred (lazy gem inference) |
| `TypeVariable` | `Elem`, `K`, `V` | RBS type variables |
| `SelfType` | `self` | RBS self type (substituted at resolution) |
| `ForwardingArgs` | `...` | Forwarding parameter type |
| `MethodSignature` | `(String) -> Integer` | Method/Proc signature with params and return type |

### SignatureRegistry (`lib/type_guessr/core/registry/signature_registry.rb`)

Preloads stdlib RBS signatures and provides O(1) hash lookup for method return types.

**Key features:**
- Preloads all stdlib RBS method signatures at startup (~250ms, ~10MB memory)
- O(1) hash lookup instead of lazy DefinitionBuilder calls
- `lookup(class_name, method_name)` - Find instance method entry
- `lookup_class_method(class_name, method_name)` - Find class method entry
- `get_method_return_type(class_name, method_name, arg_types)` - Get return type with overload resolution
- `get_block_param_types(class_name, method_name)` - Get block parameter types

**MethodEntry:**
- Wraps RBS method types for a single method
- Handles overload resolution based on argument types
- Caches block parameter type computation

**Lookup order (in Resolver):**
1. MethodRegistry (project methods)
2. SignatureRegistry (stdlib RBS)

### NodeKeyGenerator (`lib/type_guessr/core/node_key_generator.rb`)

Single source of truth for node key format. Ensures consistency between IR node generation (PrismConverter) and hover/type inference lookups (Hover, TypeInferrer).

**Key methods:** `local_write`, `local_read`, `ivar_write`, `ivar_read`, `call`, `def_node`, etc.

### NodeContextHelper (`lib/type_guessr/core/node_context_helper.rb`)

Bridges ruby-lsp's `NodeContext` and TypeGuessr's IR node key format.

**Key methods:**
- `generate_scope_id(node_context)` - Extract scope (class + method) from Prism node context
- `generate_node_hash(prism_node)` - Map Prism node types to node key format

### TypeSimplifier (`lib/type_guessr/core/type_simplifier.rb`)

Simplifies complex union types.

**Key features:**
- Normalize type representations
- Reduce union complexity for cleaner display

## MCP Server (`lib/type_guessr/mcp/`)

Standalone MCP server that exposes type inference to AI tools (e.g., Claude Code) via stdio transport.

### Components

- **Server** (`server.rb`): Indexes project on startup, defines MCP tools, starts stdio transport
- **StandaloneRuntime** (`standalone_runtime.rb`): Mirrors RuntimeAdapter's query interface without ruby-lsp's GlobalState dependency
- **FileWatcher** (`file_watcher.rb`): Polls project directory for .rb file changes using mtime-based detection

### MCP Tools

| Tool | Input | Output |
|------|-------|--------|
| `infer_type` | file_path, line, column | Inferred type at position |
| `get_method_signature` | class_name, method_name | Parameter and return types |
| `search_methods` | query pattern | Matching method definitions |

### Startup Flow

```
exe/type-guessr mcp [project_path]
    │
    ├── RubyIndexer: index all project files (class/method definitions)
    ├── Build StandaloneRuntime (converter, registries, resolver)
    ├── TypeGuessr: index all project files (IR nodes, signatures)
    │
    ▼
MCP::Server → StdioTransport.open (blocks, handles JSON-RPC)
```

## Data Flow

### Initial Indexing

```
start_indexing (background thread)
    │
    ▼
traverse_file(uri) for each file
    │
    ├── File.read(file_path)
    ├── Prism.parse(source)              ← Outside mutex (CPU-bound)
    │
    ▼
@mutex.synchronize
    ├── location_index.remove_file(file_path)
    ├── Context.new(file_path:, location_index:, method_registry:, ...)
    ├── PrismConverter.convert(stmt, context)  ← Nodes registered inline via Context
    │
    ▼
@mutex.synchronize { finalize! }         ← ONCE after all files
signature_registry.preload()             ← Load all stdlib RBS signatures
```

### File Reindexing (on save)

```
index_file(uri, document) / index_source(uri_string, source)
    │
    ├── Prism.parse(source)
    │
    ▼
@mutex.synchronize
    ├── location_index.remove_file(file_path)
    ├── resolver.clear_cache
    ├── Context.new(file_path:, location_index:, method_registry:, ...)
    ├── PrismConverter.convert(stmt, context)  ← Nodes registered inline
    ├── finalize!
```

### Hover Request

```
Hover.add_hover_content(prism_node)
    │
    ├── NodeContextHelper.generate_scope_id(node_context)
    ├── NodeKeyGenerator.local_read(name, offset)  ← Build node key
    │
    ▼
@runtime_adapter.find_node_by_key(node_key)
    │
    ├── @mutex.synchronize
    ├── location_index.find_by_key(node_key)
    │
    ▼
@runtime_adapter.infer_type(ir_node)
    │
    ├── @mutex.synchronize
    ├── resolver.infer(ir_node)  ← Traverses dependency graph
    │
    ▼
result.type.to_s
    │
    ▼
response_builder.push(content)
```

## Thread Safety

RuntimeAdapter uses a single Mutex to protect:
- `@location_index` modifications
- `@resolver` access
- Cache operations

**Synchronized operations:**
- `find_node_by_key` - read from index
- `infer_type` - read from resolver (uses cache)
- `index_file` / `index_source` - write to index + registries
- `traverse_file` - write to index + registries
- `finalize!` - finalize index (no-op in current key-based implementation)

**Outside mutex (CPU-bound, no shared state):**
- File reading
- Prism parsing
- IR node conversion

## Known Issues

### File Path Mismatch Problem

The main issue is that file_path format may differ between:
1. Initial indexing: `traverse_file` uses `uri.to_standardized_path`
2. Reindexing: `index_source` uses URI parsing logic

If these don't match, `remove_file` won't clear the old data, causing stale entries.
