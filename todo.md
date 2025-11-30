# TypeGuessr TODO

> Items are ordered by priority (top = highest)

---

### [BUG] Scope Isolation Not Working for Local Variables
- [ ] `type_resolver.rb` `collect_method_calls` leaks method calls from other scopes when scope_id mismatch
- [ ] `VariableTypeResolver.generate_scope_id` cannot find enclosing method when `node_context.call_node` is nil
- [ ] Need to add AST re-parse workaround to find enclosing method (potential performance issue)

**Reproduction code:**
```ruby
# When same parameter name exists in different methods
class Foo
  def method_a(context)
    @ctx = context  # no method calls on context
  end

  def method_b(context)
    context.name   # calls context.name
    context.age    # calls context.age
  end
end

# Expected behavior:
# - hover on context in method_a: method_calls = []
# - hover on context in method_b: method_calls = ["name", "age"]

# Bug behavior (before fix):
# - hover on context in method_a: method_calls = ["name", "age"]  # leaked from other scope!
```

**Root cause:**
1. `type_resolver.rb` `collect_method_calls` has fallback logic that searches all scopes when exact scope_id match fails
2. `VariableTypeResolver.generate_scope_id` cannot find method name when `node_context.call_node` is nil

**Fix approach:**
1. `type_resolver.rb`: Apply strict scope matching for local variables (remove fallback)
2. `variable_type_resolver.rb`: Add AST re-parse logic to find enclosing method

**TODO:**
- [ ] Investigate finding enclosing method without AST re-parse (use Ruby LSP API)
- [ ] Performance testing needed

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
