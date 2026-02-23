# Literal Type Inference

This document is auto-generated from tests tagged with `:doc`.

> `[x]` marks the cursor position where hover was triggered.

## Basic literals

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
[i]tems  # Guessed Type: []
```

### Hash literal

```ruby
data = {}
[d]ata  # Guessed Type: { }
```

### Symbol literal

```ruby
status = :active
[s]tatus  # Guessed Type: Symbol
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

## Range literals

### inclusive range (0..1)

```ruby
def foo
  0..1
end
[r] = foo  # Guessed Type: Range[Integer]
```

### endless range (0..)

```ruby
def bar
  0..
end
[r] = bar  # Guessed Type: Range[Integer]
```

### beginless range (..1)

```ruby
def baz
  ..1
end
[r] = baz  # Guessed Type: Range[Integer]
```

### nil range (nil..nil)

```ruby
def qux
  nil..nil
end
[r] = qux  # Guessed Type: Range[nil]
```

## Complex number literal

### imaginary number (1i)

```ruby
def check
  1i
end
[c] = check  # Guessed Type: Complex
```

## Rational number literal

### rational number (1r)

```ruby
def check
  1r
end
[r] = check  # Guessed Type: Rational
```

## Regexp literal

### simple regexp (/foo/)

```ruby
def check1
  /foo/
end
[r] = check1  # Guessed Type: Regexp
```

### regexp with interpolation

```ruby
def check2
  /foo1bar/
end
[r] = check2  # Guessed Type: Regexp
```

## Interpolated strings

### string with interpolation

```ruby
def bar(n)
  "bar"
end

def foo
  "foo#{bar(1)}"
end

[s] = foo  # Guessed Type: String
```

### string with empty interpolation

```ruby
def foo
  "foo"
end
[s] = foo  # Guessed Type: String
```

### backtick string (xstring)

```ruby
def xstring_lit(n)
  `echo foo`
end
[s] = xstring_lit(10)  # Guessed Type: String
```

### string with global variable interpolation

```ruby
def foo
  "#{Regexp.last_match(1)}"
end
[s] = foo  # Guessed Type: String
```

