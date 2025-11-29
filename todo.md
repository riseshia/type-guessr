# TypeGuessr TODO

> Items are ordered by priority (top = highest)

---

### Remove Write Nodes from HOVER_NODE_TYPES
- [ ] Consider removing `local_variable_write`, `local_variable_target` etc.

**Context:**
- Location: `lib/ruby_lsp/type_guessr/hover.rb` line 14-30
- Write nodes trigger hover but typically users want type info when reading, not writing
- Not harmful, just unnecessary

---

### Unify Scope ID Generation
- [ ] Investigate if `ASTAnalyzer` and `VariableTypeResolver` can produce mismatched scope IDs
- [ ] Refactor both to use `ScopeResolver` consistently

**Context:**
- `ASTAnalyzer` (indexing time): uses `@class_stack`, `@method_stack`
- `VariableTypeResolver` (hover time): uses `node_context.nesting`, `node_context.call_node`
- Both call `ScopeResolver.generate_scope_id` but with potentially different inputs
- Currently works because variable types are scoped separately, but fragile

---

### Improve IndexAdapter Performance
- [ ] Consider caching `all_class_and_module_entries` result
- [ ] Or use more targeted queries instead of iterating all entries

**Context:**
- Location: `lib/type_guessr/integrations/ruby_lsp/index_adapter.rb`
- `all_class_and_module_entries` calls `@index.fuzzy_search(nil)` on every hover
- May be slow on large projects
- Currently relying on ruby-lsp's internal optimization

---

### Create Main TypeGuessr API
- [ ] Add `TypeGuessr.analyze_file(file_path)` method
- [ ] Add `TypeGuessr::Project` class for caching indexes
- [ ] Add `TypeGuessr::Core::FileAnalyzer` for single-file workflow

**Context:**
- Goal: Make core library usable independently from Ruby LSP
- Enables CLI tools, Rails integration, etc.
- Blocked by: LSP integration layer cleanup

---

### Update Tests Structure
- [ ] Move core tests to `test/type_guessr/core/`
- [ ] Move LSP tests to `test/type_guessr/integrations/ruby_lsp/`
- [ ] Add API tests for main entry points

**Context:**
- Current: All tests in `test/ruby_lsp/`
- Target: Mirror lib structure for better organization
- Blocked by: Core/integration separation completion

---

### Update Documentation
- [ ] Update README.md with architecture diagram
- [ ] Update AGENTS.md with new structure
- [ ] Create CHANGELOG.md for v0.2.0

**Context:**
- Document dual usage: Ruby LSP addon + standalone library
- Explain layer responsibilities
- Migration guide for namespace changes
