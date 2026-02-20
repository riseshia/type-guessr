# ADR-0003: Exclude Object Instance Methods from Duck Type Search

## Status

Accepted

## Context

Duck type inference searches for classes that define all methods called on a parameter.
When a parameter calls universal methods like `eql?`, `==`, or `is_a?`, the search
returns 200+ classes because every class inherits these from Object.

### The Problem

```ruby
def ==(other)
  other.is_a?(Result) && type == other.type
end
```

For `other`, called_methods = `[:is_a?, :type]`. The `is_a?` search via
`fuzzy_search` returns every class in the index (200+), which then triggers:

1. `filter_to_most_general_types` — calls `ancestors_of` 200 times
2. Result exceeds `MAX_ELEMENT_IN_UNION` (3) — returns Unknown anyway

All 200 ancestor lookups are wasted work.

### Measurement

Cold-cache profiling of 15,000 methods (out of 42,124 total):

- **322 timeouts** (>600ms) and **93 slow methods** (500–600ms)
- ~60% of slow project methods were `eql?`/`==` patterns
- `Result#==`: 908ms, `HashShape#eql?`: 516ms, `Union#eql?`: 397ms, etc.

Root cause: Object methods in `called_methods` → `fuzzy_search` explosion →
expensive `ancestors_of` calls → Unknown result (all work discarded).

## Decision

Exclude Object's public instance methods from duck type candidate search in
`CodeIndexAdapter#find_classes_defining_methods`.

These methods exist on every class, so they have zero discriminating power
for type inference. Filtering them out is equivalent to saying:
"a method present on all classes tells us nothing about which class this is."

Implementation: a hardcoded `OBJECT_METHOD_NAMES` frozen Set in CodeIndexAdapter,
checked before `fuzzy_search`. May later be replaced with dynamic RBS lookup.

## Consequences

### Positive

- **Pattern A (eql?/==) eliminated**: `Result#==` (908ms→<5ms), `HashShape#eql?` (516ms→<5ms), all `eql?`/`==` project methods resolved instantly
- **Minimal change**: 1 constant + 2 lines of filtering logic
- **No behavior change for well-typed results**: Object methods never contributed useful type discrimination
- **Gem methods also improved**: reduced timeouts from universal method searches

### Negative

- Hardcoded list requires manual updates if Object gains new public methods (rare)
- Theoretical edge case: if a parameter ONLY calls Object methods, result is now Unknown immediately instead of Unknown after expensive computation (same outcome, faster path)

### Not Addressed

- **Pattern B (large methods)**: `PrismConverter#convert` (1,845 lines, 30+ branches) still times out due to deep dependency graph explosion — requires separate depth limit or wall-time timeout
