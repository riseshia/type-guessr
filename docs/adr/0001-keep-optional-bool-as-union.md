# ADR-0001: Keep Optional and Bool Types as Union Specializations

## Status

Accepted

## Context

TypeGuessr's type system needs to represent optional types (`?Type`) and boolean types (`bool`). There are two approaches:

1. **Current approach**: Represent them as `Union` with special detection logic
   - `?String` → `Union([ClassInstance("String"), ClassInstance("NilClass")])`
   - `bool` → `Union([ClassInstance("TrueClass"), ClassInstance("FalseClass")])`

2. **Alternative**: Create dedicated `OptionalType` and `BoolType` classes
   - `?String` → `OptionalType(ClassInstance("String"))`
   - `bool` → `BoolType.new`

### Arguments for Separate Classes

- Type checking becomes simpler (`type.is_a?(OptionalType)` vs pattern matching)
- Semantic intent is clearer in the code
- Future Optional-specific features (unwrap, flatten) would be easier to add

### Arguments for Keeping Union

- Mathematically correct (Optional is a subset of Union)
- Complex unions handle naturally: `String | nil | Integer` stays as Union
- No ambiguity about `?(String | Integer)` vs `?String | Integer`
- Current implementation works well with no known issues
- Avoids Union ↔ Optional/Bool conversion complexity

## Decision

**Keep Optional and Bool as Union specializations.**

The `Union` class provides detection methods (`optional_type?`, `bool_type?`) and formats output appropriately in `to_s`. This approach:

```ruby
class Union < Type
  def to_s
    if bool_type?
      "bool"
    elsif optional_type?
      "?#{non_nil_type}"
    else
      @types.map(&:to_s).sort.join(" | ")
    end
  end

  def optional_type?
    @types.size == 2 && @types.any? { |t| nil_type?(t) }
  end

  def bool_type?
    return false unless @types.size == 2
    has_true = @types.any? { |t| t.is_a?(ClassInstance) && t.name == "TrueClass" }
    has_false = @types.any? { |t| t.is_a?(ClassInstance) && t.name == "FalseClass" }
    has_true && has_false
  end
end
```

## Consequences

### Positive

- No changes required to 12+ files and 50+ tests
- Complex union cases (e.g., `String | nil | Integer`) remain straightforward
- Type algebra stays mathematically consistent
- Single representation simplifies type normalization

### Negative

- Type detection requires method calls (`optional_type?`) instead of `is_a?` checks
- Optional-specific operations would need to be added to Union class
- Less explicit semantic distinction in the type hierarchy

### Neutral

- If a concrete use case arises requiring dedicated Optional/Bool classes, this decision can be revisited
