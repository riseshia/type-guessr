# Unsupported Cases

Intentionally unsupported type inference cases.
These are known limitations where the cost of implementation outweighs the benefit.

## Hash#dig

`Hash#dig` always returns `untyped`.

RBS defines `dig` with `untyped` return type because the nested structure
cannot be statically determined. Tracking nested Hash types through arbitrary
depth would require dependent typing, which is far beyond heuristic inference.

```ruby
result = @methods.dig(class_name, method_name)
# => untyped (expected: DefNode | nil)
```

## Argument-dependent return types

Methods whose return type depends on the runtime value of arguments.
Requires inspecting argument values at inference time, which is a fundamentally
different capability from signature-based type lookup.

```ruby
# create_table :users do |t|
#   t.string :name
#   t.string :email
#   t.integer :age
# end
User.sum(:age)              # => untyped (expected: Numeric — depends on column type)
User.pick(:name)            # => untyped (expected: String? — depends on column type)
User.pick(:name, :email)    # => untyped (expected: Array? — depends on arg count)
User.find_each { |u| u }   # => untyped (expected: nil — depends on block presence)
```
