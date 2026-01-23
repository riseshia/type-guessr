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
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐                              │
│  │  Config   │  │DebugServer│  │ GraphBuilder  │                              │
│  │           │  │           │  │               │                              │
│  │ - yaml    │  │ - http    │  │ - node graph  │                              │
│  │ - env     │  │ - inspect │  │ - prism coord │                              │
│  └───────────┘  └───────────┘  └───────────────┘                              │
└───────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                                 Core Layer                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ PrismConverter│  │  RBSConverter │  │ LocationIndex │  │   Resolver    │   │
│  │               │  │               │  │               │  │               │   │
│  │ Prism AST→IR  │  │ RBS→Types     │  │ (file,line)   │  │ IR Node→Type  │   │
│  │               │  │               │  │  → IR Node    │  │               │   │
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘   │
│                                                                                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │   IR Nodes    │  │    Types      │  │  RBSProvider  │  │SignatureProvdr│   │
│  │               │  │               │  │               │  │               │   │
│  │ - LiteralNode │  │ - ClassInst   │  │ - method sigs │  │ - sig format  │   │
│  │ - Local*Node  │  │ - ArrayType   │  │ - return types│  │ - param types │   │
│  │ - IVar*Node   │  │ - HashType    │  │               │  │               │   │
│  │ - CVar*Node   │  │ - HashShape   │  │               │  │               │   │
│  │ - CallNode    │  │ - RangeType   │  │               │  │               │   │
│  │ - ParamNode   │  │ - Union       │  │               │  │               │   │
│  │ - DefNode     │  │ - Singleton   │  │               │  │               │   │
│  │ - SelfNode    │  │ - TypeVar     │  │               │  │               │   │
│  │ - ReturnNode  │  │               │  │               │  │               │   │
│  └───────────────┘  └───────────────┘  └───────────────┘  └───────────────┘   │
│                                                                                │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │TypeSimplifier │  │    Logger     │  │MethodRegistry │  │VariableRegstry│   │
│  │               │  │               │  │               │  │               │   │
│  │ - union simp  │  │ - debug log   │  │ - register    │  │ - ivar store  │   │
│  │ - normalize   │  │               │  │ - lookup      │  │ - cvar store  │   │
│  │               │  │               │  │ - inheritance │  │ - inheritance │   │
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
| `ConstantNode` | Constants | Points to assigned value |
| `ClassModuleNode` | Class/module definitions | Contains method DefNodes |
| `SelfNode` | Self reference | None (resolved from class context) |
| `ReturnNode` | Explicit return statement | Points to return value node |

### PrismConverter (`lib/type_guessr/core/converter/prism_converter.rb`)

Converts Prism AST to node graph at indexing time.

**Key responsibilities:**
- Convert Prism nodes to IR nodes
- Track variable definitions via Context
- Handle method calls and track called methods on variables
- Handle indexed assignment (`a[:key] = value`) for Hash type tracking

**Context:**
- Maintains variable → IR node mapping within a scope
- Enables variable reassignment tracking
- Handles Hash indexed assignment type updates

### RBSConverter (`lib/type_guessr/core/converter/rbs_converter.rb`)

Converts RBS types to internal type system.

**Key responsibilities:**
- Parse RBS type syntax
- Convert to TypeGuessr::Core::Types representations
- Isolate RBS dependencies from core inference logic

### LocationIndex (`lib/type_guessr/core/index/location_index.rb`)

O(1) lookup from node key to node.

**Key features:**
- Entries sorted by (line, col_range.begin) for binary search
- Prefers assignment nodes over read nodes at same position
- Per-file storage with `finalize!` for sorting

### Resolver (`lib/type_guessr/core/inference/resolver.rb`)

Resolves nodes to types by traversing the dependency graph.

**Key features:**
- Caches inference results per node
- Handles RBS method signature lookup
- Resolves block parameter types from receiver's element type
- Method-based type inference via called method resolution
- Uses injected `MethodRegistry` and `VariableRegistry` for storage

### MethodRegistry (`lib/type_guessr/core/registry/method_registry.rb`)

Stores and retrieves project method definitions (DefNode).

**Key features:**
- `register(class_name, method_name, def_node)` - Store method definition
- `lookup(class_name, method_name)` - Find method (supports inheritance via ancestry_provider)
- `methods_for_class(class_name)` - Get direct methods for a class (debug server)
- `search(pattern)` - Search methods by pattern (debug server)

### VariableRegistry (`lib/type_guessr/core/registry/variable_registry.rb`)

Stores and retrieves instance/class variable definitions.

**Key features:**
- `register_instance_variable(class_name, name, write_node)` - Store instance variable
- `lookup_instance_variable(class_name, name)` - Find instance variable (supports inheritance)
- `register_class_variable(class_name, name, write_node)` - Store class variable
- `lookup_class_variable(class_name, name)` - Find class variable

### Types (`lib/type_guessr/core/types.rb`)

Type representations:

| Type | Example | Description |
|------|---------|-------------|
| `ClassInstance` | `String`, `Integer` | Single class type |
| `SingletonType` | `singleton(User)` | Class object itself (singleton class) |
| `ArrayType` | `Array[Integer]` | Array with element type |
| `HashType` | `Hash[Symbol, String]` | Hash with key/value types |
| `HashShape` | `{ a: Integer, b: String }` | Hash with known fields |
| `RangeType` | `Range[Integer]` | Range with element type |
| `Union` | `Integer \| String` | Union of types |
| `Unknown` | `untyped` | Unknown type (singleton) |
| `TypeVariable` | `Elem`, `K`, `V` | RBS type variables |
| `SelfType` | `self` | RBS self type (substituted at resolution) |
| `ForwardingArgs` | `...` | Forwarding parameter type |

### RBSProvider (`lib/type_guessr/core/rbs_provider.rb`)

Provides RBS method signatures and return types.

**Key features:**
- Method signature lookup from RBS definitions
- Return type resolution
- Type variable substitution for generics

### SignatureProvider (`lib/type_guessr/core/signature_provider.rb`)

Generates method signatures from inferred types.

**Key features:**
- Format parameter types for display
- Format return types for hover UI

### TypeSimplifier (`lib/type_guessr/core/type_simplifier.rb`)

Simplifies complex union types.

**Key features:**
- Normalize type representations
- Reduce union complexity for cleaner display

## Data Flow

### Initial Indexing

```
start_indexing (background thread)
    │
    ▼
traverse_file(uri)
    │
    ├── File.read(file_path)
    ├── Prism.parse(source)
    ├── PrismConverter.convert(stmt, context)  ← Creates IR nodes
    │
    ▼
@mutex.synchronize
    ├── location_index.remove_file(file_path)
    ├── index_node_recursively(file_path, node)  ← Adds to LocationIndex
    │
    ▼
finalize!  ← Sort entries for binary search (ONCE after all files)
```

### File Reindexing (on save)

```
workspace_did_change_watched_files
    │
    ▼
reindex_file(uri)
    │
    ├── File.read(file_path)
    │
    ▼
index_source(uri_string, source)
    │
    ├── Prism.parse(source)
    ├── PrismConverter.convert(stmt, context)
    │
    ▼
@mutex.synchronize
    ├── location_index.remove_file(file_path)
    ├── index_node_recursively(file_path, node)
    ├── finalize!
```

### Hover Request

```
Hover.add_hover_content(prism_node)
    │
    ├── Extract line/column from Prism node
    │
    ▼
@runtime_adapter.find_node_at(nil, line, column)
    │
    ├── @mutex.synchronize
    ├── location_index.find(file_path, line, column)
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
- `find_node_at` - read from index
- `infer_type` - read from resolver (uses cache)
- `index_file` / `index_source` - write to index
- `traverse_file` - write to index
- `finalize!` - sort index entries

**Outside mutex (CPU-bound, no shared state):**
- File reading
- Prism parsing
- IR node conversion

## Known Issues

### File Path Mismatch Problem

The main issue is that file_path format may differ between:
1. Initial indexing: `traverse_file` uses `uri.full_path.to_s`
2. Reindexing: `index_source` uses URI parsing logic

If these don't match, `remove_file` won't clear the old data, causing stale entries.
