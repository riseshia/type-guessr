# TypeGuessr TODO

> Items are ordered by priority (top = highest)

---

### Resolve fully qualified type names for index lookup
- [ ] `ASTAnalyzer#extract_class_name_from_receiver` returns short name (e.g., `VariableTypeResolver`)
- [ ] ruby-lsp's index requires fully qualified name (e.g., `RubyLsp::TypeGuessr::VariableTypeResolver`)
- [ ] Need to resolve short names to FQN using nesting context or index lookup

**Context:**
- `@type_resolver.resolve_type(node)` hover fails because `GuessedType.new("VariableTypeResolver")` returns short name
- `@index["VariableTypeResolver"]` returns 0, but `@index["RubyLsp::TypeGuessr::VariableTypeResolver"]` returns 1
- Options: (1) Track nesting in ASTAnalyzer, (2) Resolve in TypeInferrer using `@index.resolve`

**Reproduction:**
```ruby
# In lib/ruby_lsp/type_guessr/hover.rb, hover on `resolve_type` in:
#   type_info = @type_resolver.resolve_type(node)
#
# Expected: Guessed receiver: VariableTypeResolver (with method signature)
# Actual: No hover content (ruby-lsp can't find method because short name not in index)
#
# Debug output:
#   [TypeGuessr::TypeInferrer] Guessed type: VariableTypeResolver
#   [TypeGuessr::TypeInferrer] Index entries for 'VariableTypeResolver': 0
#   [TypeGuessr::TypeInferrer] Index entries for 'RubyLsp::TypeGuessr::VariableTypeResolver': 1
```

---

### Create Main TypeGuessr API
- [ ] Add `TypeGuessr.analyze_file(file_path)` method
- [ ] Add `TypeGuessr::Project` class for caching indexes
- [ ] Add `TypeGuessr::Core::FileAnalyzer` for single-file workflow

**Context:**
- Goal: Make core library usable independently from Ruby LSP
- Enables CLI tools, Rails integration, etc.
- Blocked by: LSP integration layer cleanup
