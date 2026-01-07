# TypeGuessr Architecture

## Overview

TypeGuessr is a Ruby LSP addon that provides heuristic type inference without requiring explicit type annotations. It converts Prism AST nodes into a graph structure optimized for type inference.

## Architecture Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    Ruby LSP Integration                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Addon     │  │   Hover     │  │   RuntimeAdapter    │  │
│  │             │  │             │  │                     │  │
│  │ - activate  │  │ - listeners │  │ - index management  │  │
│  │ - file      │  │ - type      │  │ - type inference    │  │
│  │   watching  │  │   display   │  │ - mutex sync        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                         Core Layer                           │
│  ┌─────────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │ PrismConverter  │  │ LocationIdx │  │    Resolver     │  │
│  │                 │  │             │  │                 │  │
│  │ Prism AST → IR  │  │ (file,line) │  │ IR Node → Type  │  │
│  │                 │  │  → IR Node  │  │                 │  │
│  └─────────────────┘  └─────────────┘  └─────────────────┘  │
│                                                              │
│  ┌─────────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   IR Nodes      │  │    Types    │  │  RBSProvider    │  │
│  │                 │  │             │  │                 │  │
│  │ - LiteralNode   │  │ - ClassInst │  │ - method sigs   │  │
│  │ - VariableNode  │  │ - ArrayType │  │ - return types  │  │
│  │ - CallNode      │  │ - HashShape │  │                 │  │
│  │ - ParamNode     │  │ - Union     │  │                 │  │
│  │ - DefNode       │  │             │  │                 │  │
│  │ - BlockParamSlot│  │             │  │                 │  │
│  └─────────────────┘  └─────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### Nodes (`lib/type_guessr/core/ir/nodes.rb`)

Nodes form a reverse dependency graph where each node points to the nodes it depends on for type inference.

| Node Type | Purpose | Dependency |
|-----------|---------|------------|
| `LiteralNode` | Literals (string, integer, array, hash) | None (leaf node) |
| `VariableNode` | Variable assignments and reads | Points to assigned value node |
| `ParamNode` | Method parameters | Points to default value (called_methods tracked for inference) |
| `CallNode` | Method calls | Points to receiver + args |
| `DefNode` | Method definitions | Points to body (return value) |
| `BlockParamSlot` | Block parameters | Filled by CallNode inference |
| `MergeNode` | Control flow merge (if/else) | Points to all branches |
| `ConstantNode` | Constants | Points to assigned value |
| `ClassModuleNode` | Class/module definitions | Contains method DefNodes |

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

### Types (`lib/type_guessr/core/types.rb`)

Type representations:

| Type | Example | Description |
|------|---------|-------------|
| `ClassInstance` | `String`, `Integer` | Single class type |
| `ArrayType` | `Array[Integer]` | Array with element type |
| `HashType` | `Hash[Symbol, String]` | Hash with key/value types |
| `HashShape` | `{ a: Integer, b: String }` | Hash with known fields |
| `Union` | `Integer \| String` | Union of types |
| `Unknown` | `untyped` | Unknown type (singleton) |
| `TypeVariable` | `Elem`, `K`, `V` | RBS type variables |

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

See `todo.md` for current bugs and investigation notes.

### File Path Mismatch Problem

The main issue is that file_path format may differ between:
1. Initial indexing: `traverse_file` uses `uri.full_path.to_s`
2. Reindexing: `index_source` uses URI parsing logic

If these don't match, `remove_file` won't clear the old data, causing stale entries.
