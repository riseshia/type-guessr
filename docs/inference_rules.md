# Type Inference Rules

This document is auto-generated from tests tagged with `:doc`.

## Literal Type Inference

### String literal

```ruby
name = "John"
[n]ame  # Guessed Type: String
```

### Integer literal

```ruby
count = 42
[c]ount  # Guessed Type: Integer
```

### Float literal

```ruby
price = 19.99
[p]rice  # Guessed Type: Float
```

### Array literal

```ruby
items = []
[i]tems  # Guessed Type: Array
```

### Hash literal

```ruby
data = {}
[d]ata  # Guessed Type: Hash
```

### Symbol literal

```ruby
status = :active
[s]tatus  # Guessed Type: Symbol
```

### Range literal

```ruby
numbers = 1..10
[n]umbers  # Guessed Type: Range
```

### Regexp literal

```ruby
pattern = /[a-z]+/
[p]attern  # Guessed Type: Regexp
```

### NilClass literal

```ruby
value = nil
[v]alue  # Guessed Type: nil
```

### Interpolated string

```ruby
name = "Alice"
greeting = "Hello #{name}"
[g]reeting  # Guessed Type: String
```

## Array Type Inference Edge Cases

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

### Nested array

```ruby
nested = [[1, 2], [3, 4]]
[n]ested  # Guessed Type: Array[Array[Integer]]
```

## .new Call Type Inference

### Simple class

```ruby
class User
end

user = User.new
use[r]  # Guessed Type: User
```

### Namespaced class

```ruby
module Admin
  class User
  end
end

admin = Admin::User.new
adm[i]n  # Guessed Type: Admin::User
```

### .new with arguments

```ruby
class User
end

use[r] = User.new("name", 20)  # Guessed Type: User
user
```

### Deeply nested namespace

```ruby
module A
  module B
    module C
      class D
      end
    end
  end
end

obj[ ]= A::B::C::D.new  # Guessed Type: A::B::C::D
obj
```

## FlowAnalyzer Integration

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

