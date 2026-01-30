# ADR-0002: Defer `.new` Go to Definition → `initialize` Redirect

## Status

Accepted

## Context

When a user invokes "Go to Definition" on `.new` calls, nothing happens:

```ruby
class MyClass
  def initialize(value)
    @value = value
  end
end

obj = MyClass.new(10)  # Go to Definition on .new → no result
```

### Why This Happens

- `.new` is a built-in Ruby class method with no source location
- ruby-lsp's Definition Provider doesn't know where to navigate
- **Hover already works** - TypeGuessr maps `.new` → `initialize` signature

### Potential Solution

Extend ruby-lsp's Definition listener:

```ruby
# addon.rb
def create_definition_listener(response_builder, uri, dispatcher)
  # Detect .new calls
  # Redirect to initialize method location
end
```

### Risks

1. **Internal API dependency** - `create_definition_listener` is an internal extension point
2. **ruby-lsp version coupling** - API may change between versions
3. **Maintenance burden** - Must track ruby-lsp updates and adapt
4. **Conflict potential** - May interfere with ruby-lsp's own definition handling

## Decision

**Defer implementation until ruby-lsp provides a stable extension point or built-in support.**

Current workarounds:
- Hover on `.new` shows `initialize` signature (already working)
- Users can manually navigate to the class and find `initialize`

## Consequences

### Positive

- No dependency on ruby-lsp internals
- No maintenance burden from tracking ruby-lsp API changes
- Focus development effort on core type inference improvements

### Negative

- Suboptimal UX for "Go to Definition" on `.new` calls
- Users must use workarounds

### Re-evaluation Triggers

- ruby-lsp adds official API for custom definition providers
- ruby-lsp implements `.new` → `initialize` navigation natively
- User demand significantly increases
