# ADR-0006: Keep Shared called_methods Array Between WriteNode and ReadNode

## Status

Accepted

## Context

`WriteNode` and `ReadNode` for the same variable share a single `called_methods` array by reference:

```ruby
# In Context
called_methods = []
write_node = WriteNode.new(..., called_methods: called_methods)
read_node = ReadNode.new(..., called_methods: called_methods)
```

When a method is called on a variable (`x.foo`), the method name is appended to the shared array. Both the write and read nodes see the update immediately.

### Concerns Raised

1. Shared mutable state — unintended mutation possible
2. Conflicts with Data.define's immutability philosophy
3. Hard to trace which node modified the array during debugging

### Why Keep It

1. **It works**: No bugs have been caused by this design so far
2. **It's the simplest solution**: The alternative (separate arrays, a mediator object, or event-based propagation) adds complexity for a problem that hasn't materialized
3. **It matches the semantics**: A variable's called methods are a property of the variable, not of individual read/write sites. Sharing by reference naturally models this

## Decision

Keep the current shared array design. Do not introduce separate arrays or a mediator object.

## Revisit Condition

Re-evaluate if shared mutation causes an actual bug (e.g., methods leaking between unrelated variables, race conditions in concurrent access).
