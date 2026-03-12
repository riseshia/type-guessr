# T4: API Surface Comparison - Ground Truth

## StandaloneRuntime

**File:** `lib/type_guessr/mcp/standalone_runtime.rb`

### Public Methods (12 total)

| Line | Method | Signature | Description |
|------|--------|-----------|-------------|
| 20-32 | `initialize` | `(converter:, location_index:, signature_registry:, method_registry:, ivar_registry:, cvar_registry:, resolver:, signature_builder:, code_index:)` | Constructor with dependency injection. Thread-safe via Mutex. |
| 37-57 | `index_parsed_file` | `(file_path, prism_result)` | Index a pre-parsed file (Prism::ParseResult) into IR. Also cleans method_registry. Thread-safe. |
| 61-67 | `remove_indexed_file` | `(file_path)` | Remove all indexed data for a file. Also cleans method_registry. Thread-safe. |
| 70-72 | `build_member_index!` | `()` | Delegate member_index build to code_index. |
| 76-78 | `refresh_member_index!` | `(file_uri)` | Delegate member_index refresh to code_index. |
| 81-83 | `finalize_index!` | `()` | Finalize location index after indexing. Thread-safe. |
| 86-88 | `preload_signatures!` | `()` | Preload RBS signatures for inference. |
| 94-131 | `method_signature` | `(class_name, method_name)` | Get method signature. Searches project → RBS → gem cache. Returns Hash with :source. |
| 136-140 | `method_signatures` | `(methods)` | Batch version of method_signature. Takes Array<Hash{class_name:, method_name:}>. |
| 146-176 | `method_source` | `(class_name, method_name)` | Get source code of a method. Uses method_registry + Prism re-parse. Returns Hash with :source, :file_path, :line. |
| 181-185 | `method_sources` | `(methods)` | Batch version of method_source. Takes Array<Hash{class_name:, method_name:}>. |
| 191-210 | `search_methods` | `(query, include_signatures: false)` | Search methods matching pattern. Returns Array<Hash>. Optional signatures. |

No public `attr_reader` exposed.

## RuntimeAdapter

**File:** `lib/ruby_lsp/type_guessr/runtime_adapter.rb`

### Public Attribute Readers
Line 25: `attr_reader :signature_registry, :location_index, :resolver, :method_registry`

### Public Methods (18 total, including initialize)

| Line | Method | Signature | Description |
|------|--------|-----------|-------------|
| 27-68 | `initialize` | `(global_state, message_queue = nil)` | Constructor. Creates all internal registries from ruby-lsp GlobalState. |
| 72-81 | `swap_type_inferrer` | `()` | Replace ruby-lsp's TypeInferrer with TypeGuessr's custom implementation. |
| 84-92 | `restore_type_inferrer` | `()` | Restore original TypeInferrer. |
| 97-106 | `index_file` | `(uri, document)` | Index file from URI + RubyLsp::Document. |
| 111-121 | `index_source` | `(uri_string, source)` | Index source code directly (for testing). |
| 124-126 | `build_member_index!` | `()` | Build member_index for duck type resolution. |
| 130-139 | `remove_indexed_file` | `(file_path)` | Remove indexed data. Also refreshes member_index. Thread-safe. |
| 144-148 | `find_node_by_key` | `(node_key)` | Find IR node by key (scope_id:node_hash). Returns IR::Node or nil. Thread-safe. |
| 153-157 | `infer_type` | `(node)` | Infer type for an IR node. Returns Inference::Result. Thread-safe. |
| 162-166 | `build_method_signature` | `(def_node)` | Build MethodSignature from DefNode. Thread-safe. |
| 173-202 | `build_constructor_signature` | `(class_name)` | Build constructor signature for Class.new. Checks project → RBS → default. Returns Hash with :signature, :source. |
| 208-212 | `lookup_method` | `(class_name, method_name)` | Look up DefNode by class/method. Returns DefNode or nil. Thread-safe. |
| 215-259 | `start_indexing` | `()` | Start background indexing thread. Handles gem cache, RBS preload, member_index. |
| 262-264 | `indexing_completed?` | `()` | Check if initial indexing completed. Returns Boolean. |
| 268-270 | `stats` | `()` | Get index statistics. Returns Hash. |
| 275-277 | `methods_for_class` | `(class_name)` | Get all methods for a class. Returns Hash<String, DefNode>. Thread-safe. |
| 282-294 | `search_project_methods` | `(query)` | Search methods matching pattern. Returns Array<Hash> with :node_key, :location. |
| 300-302 | `resolve_constant_name` | `(short_name, nesting)` | Resolve short constant name to FQN. Returns String or nil. |
| 309-317 | `get_rbs_method_signatures` | `(class_name, method_name)` | RBS instance method lookup with owner resolution. Returns Hash with :signatures, :owner. |
| 323-335 | `get_rbs_class_method_signatures` | `(class_name, method_name)` | RBS class method lookup with owner resolution. Returns Hash with :signatures, :owner. |

## Comparison

### (1) Methods with Same Purpose in Both

| Purpose | StandaloneRuntime | RuntimeAdapter | Difference |
|---------|-------------------|----------------|-----------|
| Initialize | `initialize(converter:, ...)` 9 kwargs | `initialize(global_state, message_queue=nil)` | SR: dependency injection; RA: creates internally from GlobalState |
| Index file | `index_parsed_file(file_path, prism_result)` | `index_file(uri, document)` + `index_source(uri_string, source)` | SR: takes pre-parsed Prism; RA: takes ruby-lsp Document or raw source |
| Remove file | `remove_indexed_file(file_path)` | `remove_indexed_file(file_path)` | Both clean method_registry; RA also refreshes member_index |
| Build member index | `build_member_index!()` | `build_member_index!()` | Same purpose, same delegation |
| Search methods | `search_methods(query, include_signatures:)` | `search_project_methods(query)` | SR: optional signatures; RA: returns :node_key, :location |
| Preload RBS | `preload_signatures!()` | *(done inside start_indexing)* | SR: explicit; RA: implicit in background thread |
| Finalize index | `finalize_index!()` | *(implicit in index_file_with_prism_result)* | SR: explicit; RA: automatic |

### (2) Methods Unique to StandaloneRuntime

| Method | Purpose |
|--------|---------|
| `method_source(class_name, method_name)` | Get method source code by name. Re-parses file with Prism to extract def range. |
| `method_sources(methods)` | Batch version of method_source. |
| `method_signature(class_name, method_name)` | High-level: look up method signature from class/method names. Searches project → RBS → gem cache. |
| `method_signatures(methods)` | Batch version of method_signature. |
| `refresh_member_index!(file_uri)` | Exposed as separate method (RA does it implicitly) |

### (3) Methods Unique to RuntimeAdapter

| Method | Purpose |
|--------|---------|
| `swap_type_inferrer()` | Replace ruby-lsp's TypeInferrer |
| `restore_type_inferrer()` | Restore original TypeInferrer |
| `index_source(uri_string, source)` | Index raw source (testing) |
| `find_node_by_key(node_key)` | Look up IR node by key |
| `infer_type(node)` | Low-level: infer type for already-indexed IR node |
| `build_method_signature(def_node)` | Build MethodSignature from DefNode |
| `build_constructor_signature(class_name)` | Handle Class.new return type (project → RBS → default) |
| `lookup_method(class_name, method_name)` | Direct DefNode lookup |
| `start_indexing()` | Background indexing thread with gem cache |
| `indexing_completed?()` | Check indexing status |
| `stats()` | Index statistics |
| `methods_for_class(class_name)` | Get all methods for a class |
| `resolve_constant_name(short_name, nesting)` | Constant name resolution |
| `get_rbs_method_signatures(class_name, method_name)` | RBS instance method signatures with owner resolution |
| `get_rbs_class_method_signatures(class_name, method_name)` | RBS class method signatures with owner resolution |
| `attr_reader :signature_registry, :location_index, :resolver, :method_registry` | Direct component access |

### Key Architectural Differences

| Aspect | StandaloneRuntime | RuntimeAdapter |
|--------|-------------------|----------------|
| Role | Standalone MCP inference engine | ruby-lsp integration layer |
| Dependency model | Injection (caller builds deps) | Wraps GlobalState (builds internally) |
| File input | Pre-parsed Prism::ParseResult | URI + Document or source string |
| Query model | Name-based (class+method → source/signature) | Indexed lookup (find node → infer) |
| Async | None (all synchronous) | Background indexing thread |
| Gem support | None | Signature caching + on-demand inference |
| RBS access | Basic lookup | Advanced (owner resolution, instance vs class) |
| Access pattern | Methods only | Methods + attr_readers |
| API style | High-level, name-based (method_source, method_signature, batch variants) | Low-level primitives (find_node_by_key, infer_type) |
