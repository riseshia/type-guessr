# ADR-0005: No Cross-File Variable Resolution

## Status

Accepted

## Context

TypeGuessr infers types at **file/method scope**. Instance variables (`@ivar`) and class variables (`@@cvar`) are resolved within the file where they are written.

A cross-file resolution feature was proposed:
- Collect `@ivar` writes across multiple files (e.g., `initialize` in file A, reader in file B)
- Aggregate class variable writes across inheritance hierarchies
- Resolve variable types by combining information from multiple files

### Why Not

TypeGuessr's core design deliberately limits inference scope to **single file / single method** to keep complexity manageable:

1. **Complexity budget**: Cross-file resolution requires dependency tracking between files, cache invalidation on file changes, and order-dependent resolution — a significant jump in implementation and maintenance complexity
2. **Diminishing returns**: Most instance variables are written and read within the same class file. The common case already works
3. **Consistency**: All other inference (local variables, parameters, method calls) operates within file/method boundaries. Cross-file variables would be the only exception

## Decision

Do not implement cross-file variable resolution. Keep inference scoped to file/method boundaries.

## Consequences

- `@ivar` written in one file and read in another file will be `untyped` (unless `ivar_registry` resolves it within the same indexing pass)
- Class variable inheritance across files will not be tracked
- Simpler implementation, predictable performance, easier debugging

## Revisit Condition

Re-evaluate only when cross-file resolution becomes a significant blocker for practical type inference quality — i.e., other inference capabilities are mature and this gap is clearly the bottleneck.
