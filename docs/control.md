# Control Type Inference

This document is auto-generated from tests tagged with `:doc`.

> `[x]` marks the cursor position where hover was triggered.

## If-else branches

### ternary operator with different types

```ruby
def foo(n)
  n ? 1 : "str"
end
[r] = foo(true)  # Guessed Type: Integer | String
```

### if modifier with assignment

```ruby
def bar(n)
  n = 1 if n
  n
end
[r] = bar(true)  # Guessed Type: untyped
```

### unless modifier with assignment

```ruby
def baz(n)
  n = 1 unless n
end
[r] = baz(nil)  # Guessed Type: ?Integer
```

### if-else with symbol literals

```ruby
def foo
  if true
    :ok
  else
    :fail
  end
end
[r] = foo  # Guessed Type: Symbol
```

## Case expressions

### case with all branches returning different types

```ruby
def foo(n)
  case n
  when 1
    1
  when 2
    "str"
  else
    1.0
  end
end
[r] = foo(1)  # Guessed Type: Float | Integer | String
```

### case with raise in else clause

```ruby
def baz(n)
  case n
  when 1
    1
  when 2
    "str"
  else
    raise
  end
end
[r] = baz(1)  # Guessed Type: Integer | String
```

### case with all empty branches

```ruby
def qux(n)
  case n
  when 1
  when 2
  else
  end
end
[r] = qux(1)  # Guessed Type: nil
```

### case without predicate

```ruby
def without_predicate(n)
  case
  when true
    1
  end
end
[r] = without_predicate(nil)  # Guessed Type: ?Integer
```

## Variable reassignment in control flow

### Conditional reassignment

```ruby
def foo(flag)
  x = 1
  if flag
    x = "string"
  end
  [x]  # Guessed Type: Integer | String
end
```

### Type within branch

```ruby
def foo(flag)
  x = 1
  if flag
    x = "string"
    [x]  # Guessed Type: String
  end
end
```

### Simple reassignment

```ruby
def foo
  x = 1
  x = "string"
  [x]  # Guessed Type: String
end
```

### reassignment in non-first-line method

```ruby
class MyClass
  def some_other_method
    # filler
  end

  def foo
    x = 1
    x = "string"
    [x]  # Guessed Type: String
  end
end
```

### instance variable fallback

```ruby
class Foo
  def bar
    @instance_var = "test"
    [@]instance_var  # Guessed Type: String
  end
end
```

### elsif branches

```ruby
def foo(flag)
  x = 1
  if flag == 1
    x = "string"
  elsif flag == 2
    x = :symbol
  end
  [x]  # Guessed Type: Integer | String | Symbol
end
```

### ||= compound assignment with nil lhs

```ruby
def foo
  x = nil
  x ||= 1
  [x]  # Guessed Type: Integer
end
```

### ||= compound assignment with truthy lhs

```ruby
def foo
  x = 1
  x ||= "hello"
  [x]  # Guessed Type: Integer
end
```

### hash access with || fallback (variable key)

```ruby
def foo(key)
  h = {}
  keys = h[key] || []
  [k]eys  # Guessed Type: []
end
```

### &&= compound assignment

```ruby
def foo
  x = 1
  x &&= "string"
  [x]  # Guessed Type: Integer | String
end
```

### += compound assignment

```ruby
def foo
  x = "hello"
  x += " world"
  [x]  # Guessed Type: String
end
```

### guard clause with return

```ruby
def foo(x)
  return unless x
  y = 1
  [y]  # Guessed Type: Integer
end
```

## Guard Clause Type Narrowing

### return unless local_var narrows type

```ruby
def foo(x)
  x = nil
  x = "hello" if true
  return unless x
  [x]  # Guessed Type: String
end
```

### return nil unless @ivar narrows instance variable

```ruby
class Foo
  def initialize(flag)
    @data = if flag
              [1, 2, 3]
            else
              nil
            end
  end

  def process
    return nil unless @data
    [@]data  # Guessed Type: [Integer, Integer, Integer]
  end
end
```

### raise unless local_var narrows type

```ruby
def bar(x)
  x = nil
  x = 42 if true
  raise "error" unless x
  [x]  # Guessed Type: Integer
end
```

## Explicit Return Handling

### early return with guard clause

```ruby
class Test
  def [f]lip(flag = true)  # Signature: (?true flag) -> bool
    return false if flag
    flag
  end
end
```

### multiple explicit returns

```ruby
class Test
  def [c]lassify(n)  # Signature: (untyped n) -> String
    return "negative" if n < 0
    return "zero" if n == 0
    "positive"
  end
end
```

