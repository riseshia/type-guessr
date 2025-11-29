# TypeGuessr TODO

> Items are ordered by priority (top = highest)

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

### Create Main TypeGuessr API
- [ ] Add `TypeGuessr.analyze_file(file_path)` method
- [ ] Add `TypeGuessr::Project` class for caching indexes
- [ ] Add `TypeGuessr::Core::FileAnalyzer` for single-file workflow

**Context:**
- Goal: Make core library usable independently from Ruby LSP
- Enables CLI tools, Rails integration, etc.
- Blocked by: LSP integration layer cleanup
