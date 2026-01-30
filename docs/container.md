# Container Type Inference

This document is auto-generated from tests tagged with `:doc`.

> `[x]` marks the cursor position where hover was triggered.

## Array type inference

### Homogeneous integer array

```ruby
nums = [1, 2, 3]
[n]ums  # Guessed Type: Array[Integer]
```

### Mixed array with 2 types

```ruby
mixed = [1, "a"]
[m]ixed  # Guessed Type: Array[Integer | String]
```

### Mixed array with 3 types

```ruby
mixed = [1, "a", :sym]
[m]ixed  # Guessed Type: Array[Integer | String | Symbol]
```

### Array with 4+ types

```ruby
mixed = [1, "a", :sym, 1.0]
[m]ixed  # Guessed Type: Array[Float | Integer | String | Symbol]
```

### Nested array

```ruby
nested = [[1, 2], [3, 4]]
[n]ested  # Guessed Type: Array[Array[Integer]]
```

### Deeply nested array

```ruby
deep = [[[1]]]
[d]eep  # Guessed Type: Array[Array[Array[Integer]]]
```

### array with method chaining

```ruby
def foo(a)
  a
end

foo([1, 2, 3].to_a)
[r] = [1, 2, 3].to_a  # Guessed Type: Array[Integer]
```

## Hash type inference

### Symbol-keyed hash

```ruby
user = { name: "John", age: 20 }
[u]ser  # Guessed Type: { name: String, age: Integer }
```

### String-keyed hash

```ruby
data = { "key" => "value" }
[d]ata  # Guessed Type: Hash[String, String]
```

### Mixed keys hash

```ruby
mixed = { name: "John", "key" => 1 }
[m]ixed  # Guessed Type: Hash[String | Symbol, Integer | String]
```

### Nested symbol-keyed hash

```ruby
user = { name: "John", address: { city: "Seoul" } }
[u]ser  # Guessed Type: { name: String, address: { city: String } }
```

### hash with symbol keys and different value types

```ruby
def foo
  {
    a: 1,
    b: "str",
  }
end

[h] = foo  # Guessed Type: { a: Integer, b: String }
```

### hash access with symbol key

```ruby
def foo
  {
    a: 1,
    b: "str",
  }
end

def bar
  foo[:a]
end

[r] = bar  # Guessed Type: Integer
```

### hash with indexed assignment

```ruby
def foo
  {
    a: 1,
    b: "str",
  }
end

def baz
  foo[:c] = 1.0
  foo[:c]
end

[r] = baz  # Guessed Type: nil
```

### hash with splat operator

```ruby
def bar
  { a: 1 }
end

def foo
  { **bar, b: 1 }
end

[h] = foo  # Guessed Type: Hash[Symbol, Integer]
```

### hash with implicit value syntax

```ruby
def create
  x = 1
  y = "str"
  { x:, y: }
end

[h] = create  # Guessed Type: { x: untyped, y: untyped }
```

## Hash indexed assignment

### empty hash

```ruby
a = {}
a[:x] = 1
[a]  # Guessed Type: { x: Integer }
```

### existing hash

```ruby
a = { a: 1 }
a[:b] = 3
[a]  # Guessed Type: { a: Integer, b: Integer }
```

### string key widens to Hash

```ruby
a = { a: 1 }
a["str_key"] = 2
[a]  # Guessed Type: Hash[String | Symbol, Integer]
```

### with string key

```ruby
a = { a: 1 }
[a]["f"] = "a"  # Guessed Type: Hash[String | Symbol, Integer | String]
```

### with symbol key

```ruby
a = { a: 1 }
[a][:b] = "x"  # Guessed Type: { a: Integer, b: String }
```

## Array indexed assignment

### with different type

```ruby
a = [1]
[a][0] = "x"  # Guessed Type: Array[Integer | String]
```

## Array << operator

### with different type

```ruby
a = [1]
[a] << "x"  # Guessed Type: Array[Integer | String]
```

## Control flow container mutation

### Hash field added in if branch

```ruby
def foo(flag)
  h = { a: 1 }
  if flag
    h[:b] = "str"
  end
  [h]  # Guessed Type: { a: Integer } | { a: Integer, b: String }
end
```

### Array element added in case branch

```ruby
def foo(n)
  arr = [1]
  case n
  when 1 then arr << "a"
  when 2 then arr << :sym
  end
  [a]rr  # Guessed Type: Array[Integer | String] | Array[Integer | Symbol]
end
```

## Sequential container expansion

### multiple Hash field additions

```ruby
h = {}
h[:a] = 1
h[:b] = "str"
h[:c] = :sym
[h]  # Guessed Type: { a: Integer, b: String, c: Symbol }
```

### multiple Array element additions

```ruby
arr = []
arr << 1
arr << "str"
arr << :sym
[a]rr  # Guessed Type: Array[Integer | String | Symbol]
```

### mixed Array operations

```ruby
arr = [1]
arr[0] = "replaced"
arr << :added
[a]rr  # Guessed Type: Array[Integer | String | Symbol]
```

## Container mutation edge cases

### container mutation followed by reassignment

```ruby
a = [1, 2]
a << "str"
a = { x: 1 }
[a]  # Guessed Type: { x: Integer }
```

