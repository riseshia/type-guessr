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

### Hash indexed assignment - empty hash

```ruby
a = {}
a[:x] = 1
[a]  # Guessed Type: { x: Integer }
```

### Hash indexed assignment - string key widens to Hash

```ruby
a = { a: 1 }
a["str_key"] = 2
[a]  # Guessed Type: Hash
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

### TrueClass literal

```ruby
flag = true
[f]lag  # Guessed Type: true
```

### FalseClass literal

```ruby
flag = false
[f]lag  # Guessed Type: false
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

### Array with 4+ types

```ruby
mixed = [1, "a", :sym, 1.0]
[m]ixed  # Guessed Type: Array[Integer | String | Symbol | Float]
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

## Class Method Calls

### File.read

```ruby
raw = File.read("dummy.txt")
[r]aw  # Guessed Type: String
```

### File.exist?

```ruby
exists = File.exist?("path")
[e]xists  # Guessed Type: bool
```

### Dir.pwd

```ruby
path = Dir.pwd
[p]ath  # Guessed Type: String
```

## Explicit Return Handling

### early return with guard clause

```ruby
class Test
  def [f]lip(flag = true)  # Signature: (?true flag) -> false | true
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

### ternary operator

```ruby
def foo(flag)
  x = flag ? 1 : "str"
  [x]  # Guessed Type: Integer | String
end
```

### ||= compound assignment

```ruby
def foo
  x = nil
  x ||= 1
  [x]  # Guessed Type: ?Integer
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

## Method Signature Display

### String#upcase

```ruby
str = "hello"
str.[u]pcase  # Signature: () -> ::String
```

### Array#map

```ruby
arr = [1, 2, 3]
arr.[m]ap { |x| x * 2 }  # Signature: [U] () { (Elem item) -> U } -> ::Array[U]
```

## Block Return Type Inference

### Array#map with block

```ruby
numbers = [1, 2, 3]
strings = numbers.map { |n| n.to_s }
[s]trings  # Guessed Type: Array[String]
```

### Array#select with block

```ruby
numbers = [1, 2, 3, 4, 5]
evens = numbers.select { |n| n.even? }
[e]vens  # Guessed Type: Array[Integer]
```

### Array#map with empty block

```ruby
numbers = [1, 2, 3]
result = numbers.map { }
[r]esult  # Guessed Type: Array[nil]
```

### Array#map with Integer arithmetic

```ruby
a = [1, 2, 3]
[b] = a.map do |num|  # Guessed Type: Array[Integer]
  num * 2
end
b
```

```ruby
a = [1, 2, 3]
b = a.map do |num|
  num * 2
end
[b]  # Guessed Type: Array[Integer]
```

### Array#map with do-end block

```ruby
numbers = [1, 2, 3]
result = numbers.map do |n|
  n.next
end
[r]esult  # Guessed Type: Array[Integer]
```

### Array#map with Integer#next

```ruby
numbers = [1, 2, 3]
result = numbers.map { |n| n.next }
[r]esult  # Guessed Type: Array[Integer]
```

