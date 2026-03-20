# ADR-0007: Keep Object Fallback for Unknown Receivers

## Status

Accepted

## Context

When a method call's receiver type is Unknown, the resolver falls through to an Object fallback that checks if the method exists on `Object` (via Kernel). This was designed for implicit-self calls like `puts` or `load "file"`, but it also triggers for explicit receiver calls like `loader.load(env: env)` when the receiver type cannot be resolved.

This produces incorrect results — e.g., `loader.load` resolves to `Kernel#load` instead of remaining Unknown.

### Known fix options

1. Guard with `unless node.receiver` before the Object fallback
2. Restrict Object fallback to a whitelist of universal methods (`to_s`, `==`, `nil?`, etc.)

### Why not fix now

- The false positive only occurs when the receiver is **already Unknown** — the inference was already failing before the fallback kicked in
- Fixing it changes the result from "wrong answer" to "no answer", which is arguably better but doesn't unlock new capabilities
- Both fix options have edge cases that need careful evaluation (option 1 breaks legitimate `Object#to_s` on unknown receivers; option 2 requires maintaining a whitelist)

## Decision

Keep the current behavior. The Object fallback applies regardless of whether a receiver is present.

## Consequences

- `loader.load` with an unresolved receiver type will incorrectly show `Object#load` (Kernel#load)
- Other ambiguous method names that happen to exist on Object/Kernel may produce false positives
- The hover result is "confidently wrong" rather than "honestly unknown" in these cases

## Revisit Condition

Re-evaluate when improving Unknown-receiver inference quality becomes a priority, or if false positives from this fallback are reported as confusing by users.
