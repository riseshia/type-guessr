# ADR-0004: Keep `<Class:X>` Scope ID Format

## Status

Accepted

## Context

`scope_id` uses the `<Class:X>` format for singleton (class) methods:

```
RBS::Environment2::<Class:Environment2>#from_loader
```

An alternative `ClassName.method` format was considered for readability:

```
RBS::Environment2::Environment2.from_loader
```

### Investigation (2026-02-24)

`scope_id` is not a display-only string — it is a **structural key** used for:

- Node indexing: 26 IR node types construct `node_key` as `"#{scope_id}:#{node_hash}"`
- Reverse extraction: `graph_builder.rb` parses scope_id from node_key by colon positions
- Singleton detection: regex `/::<Class:[^>]+>\z/` in `runtime_adapter.rb`, `code_index_adapter.rb`

**Total references: 133 across 19 files.**

### Root Cause of Current Format

The `<Class:X>` format exists for **RubyIndexer interoperability**:

```ruby
# code_index_adapter.rb — queries RubyIndexer using this format
singleton_name = "#{class_name}::<Class:#{unqualified_name}>"
```

Ruby LSP's RubyIndexer manages singleton classes with `<Class:X>` naming.
TypeGuessr matches this convention to avoid a translation layer at the boundary.

## Decision

Keep the `<Class:X>` scope_id format. Do not change.

**Reasons:**

1. Changing requires atomic update of 133 references (high risk, low reward)
2. Format is dictated by RubyIndexer convention, not TypeGuessr's choice
3. A display-only change (show `X.method` in hover UI) is possible but not worth the added complexity

## Consequences

- Internal scope_id remains `<Class:X>#method` format
- Developers reading debug output must understand this convention
- If RubyIndexer dependency is removed in the future, this decision can be revisited

## Revisit Condition

Re-evaluate only when ruby-lsp dependency is removed.
