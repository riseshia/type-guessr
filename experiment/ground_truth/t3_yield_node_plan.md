# T3: Implementation Plan (YieldNode) - Ground Truth

## Reference: CallNode as Pattern

### CallNode Definition

**File:** `lib/type_guessr/core/ir/nodes.rb` (lines 479-532)

Attributes: method (Symbol), receiver (Node|nil), args (Array<Node>), block_params (Array<BlockParamSlot>), block_body (Node|nil), has_block (Boolean), called_methods (Array<CalledMethod>), loc (Integer)

Dependencies: [receiver] + args + [block_body]
node_hash: `NodeKeyGenerator.call(method, loc)`

## Files That Need Modification

### 1. `lib/type_guessr/core/ir/nodes.rb` — Node Definition [CRITICAL]
- Add YieldNode class after CallNode
- Simpler than CallNode: no receiver, no block_body, no has_block
- Attributes: args (Array<Node>), called_methods (Array<CalledMethod>), loc (Integer)
- Dependencies: args only
- node_hash: `NodeKeyGenerator.yield(offset)`

### 2. `lib/type_guessr/core/node_key_generator.rb` — Key Generation [CRITICAL]
- Add `module_function def yield(offset) = "yield:#{offset}"`

### 3. `lib/type_guessr/core/converter/prism_converter.rb` — AST Conversion [CRITICAL]
- Add `when Prism::YieldNode` case in main `convert()` dispatch (~line 210-216)
- Add `convert_yield(prism_node, context)` method
- Extract args from `prism_node.arguments`
- Create `IR::YieldNode.new(args, called_methods, loc)`

### 4. `lib/type_guessr/core/inference/resolver.rb` — Type Inference [CRITICAL]
- Add `when IR::YieldNode` → `infer_yield(node)` in `infer_node` dispatch (~line 129)
- Implement `infer_yield(node)` method:
  - Determine enclosing method's block return type
  - Infer arg types and match to block params
  - Return block's return type or Unknown if no block

### 5. `lib/ruby_lsp/type_guessr/graph_builder.rb` — Dependency Graph [HIGH]
- Add `when ::TypeGuessr::Core::IR::YieldNode` case (~line 103)
- Add edges for each arg (no receiver edge)
- Add to `format_node_summary` (~line 262)

### 6. `lib/type_guessr/core/node_context_helper.rb` — Node Hash Bridge [HIGH]
- Add `when Prism::YieldNode` case (~line 62)
- Generate `NodeKeyGenerator.yield(offset)`

### 7. `lib/ruby_lsp/type_guessr/hover.rb` — Hover Display [HIGH]
- Add check for `IR::YieldNode` before CallNode check (~line 59-62)
- Show block parameter types and yield arg types

### 8. `lib/ruby_lsp/type_guessr/type_inferrer.rb` — Type Inferrer [MEDIUM]
- Add `when Prism::YieldNode` case (~line 30-40)
- Extract enclosing method context instead of receiver

### 9. `lib/ruby_lsp/type_guessr/debug_server.rb` — Debug Visualization [MEDIUM]
- Add YieldNode to Mermaid graph rendering (~line 637, 669-690)
- Add node type formatting and CSS styling

### 10. `lib/type_guessr/mcp/standalone_runtime.rb` — MCP API [MEDIUM]
- Add `is_a?(Core::IR::YieldNode)` check (~line 222-228)
- Include `node_type: "YieldNode"` in response

## Test Files

### 11. `spec/type_guessr/core/converter/prism_converter_spec.rb` [CRITICAL]
- There's an empty `describe "YieldNode"` skeleton at line 2419
- Add tests: simple yield, yield with args, yield in block context, multiple yields, nested yields

### 12. `spec/type_guessr/core/inference/resolver_spec.rb` [CRITICAL]
- Add `context "with YieldNode"` tests
- Test: yield return type from block, arg matching to block params, yield without block → Unknown

### 13. `spec/type_guessr/core/ir/nodes_spec.rb` [HIGH]
- Add `describe "YieldNode"` tests: creation, dependencies (args only), tree_inspect

### 14. `spec/ruby_lsp/type_guessr/graph_builder_spec.rb` [HIGH]
- Test YieldNode edge creation (args only)

### 15. `spec/type_guessr/core/node_context_helper_spec.rb` [MEDIUM]
- Test Prism::YieldNode → correct node_hash generation

## Key Design Decisions

1. **YieldNode is simpler than CallNode:** No receiver (yield is context-dependent), no block_body (yield invokes existing block, doesn't define one)
2. **Scope dependency:** YieldNode type depends on enclosing method's DefNode — resolver must traverse scope
3. **Block return type:** Yield returns the block's return type. If method called without block → Unknown
4. **No BlockParamSlot:** YieldNode doesn't create BlockParamSlots (those belong to CallNode). Yield references existing block_params from enclosing method

## Summary: Change Complexity

| File | Complexity | Estimated Lines |
|------|-----------|----------------|
| ir/nodes.rb | High (new class) | 60-80 |
| node_key_generator.rb | Low | 1 |
| prism_converter.rb | High | 35-50 |
| resolver.rb | High | 80-120 |
| graph_builder.rb | Medium | 20-30 |
| node_context_helper.rb | Low | 3-5 |
| hover.rb | Medium | 15-25 |
| type_inferrer.rb | Low | 5-10 |
| debug_server.rb | Medium | 30-40 |
| standalone_runtime.rb | Low | 5-8 |
| Test files | High | 200-300 |
