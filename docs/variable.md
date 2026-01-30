# Variable Type Inference

This document is auto-generated from tests tagged with `:doc`.

> `[x]` marks the cursor position where hover was triggered.

## Instance variables

### instance variable in same class

```ruby
class C
  def initialize(x)
    @x = 42
  end

  def foo(_)
    [@]x  # Guessed Type: Integer
  end
end
```

### instance variable in subclass

```ruby
class C
  def initialize(x)
    @x = 42
  end
end

class D < C
  def bar(_)
    @x  # Guessed Type: Integer
  end
end
```

### instance variable type changes

```ruby
class C
  def initialize(x)
    @x = "42"
  end

  def foo(_)
    [@]x  # Guessed Type: String
  end
end
```

## Class variables

### class variable in method

```ruby
class A
  def foo
    @@x = :ok
    @@[x]  # Guessed Type: Symbol
  end
end
```

### class variable at class level

```ruby
class B
  @@x = :ok

  def foo
    @@[x]  # Guessed Type: Symbol
  end
end
```

## Multiple assignment

### simple multiple assignment

```ruby
def baz
  [1, 1.0, "str"]
end

def foo
  x, y, z, w = baz
  [x]  # Guessed Type: Integer
end
```

## Operator assignment

### ||= assignment with nil

```ruby
class C
  def get_lv
    lv = nil
    lv ||= :LVar
    lv  # Guessed Type: ?Symbol
  end
end
```

### &&= assignment with value

```ruby
class C
  def get_lv
    lv = :LVar0
    lv &&= :LVar
    [l]v  # Guessed Type: Symbol
  end
end
```

## Variable scope isolation

### local vs instance variable

```ruby
class Bar
  def setup
    @user = User.new
  end

  def process
    [u]ser = "string"  # Guessed Type: String
    user
  end
end

class User
end
```

### instance variable sharing across methods

```ruby
class Chef
  def prepare_recipe
    @recipe = Recipe.new
  end

  def do_something
    @r[e]cipe  # Guessed Type: Recipe
  end
end

class Recipe
end
```

### instance variable usage before assignment

```ruby
class Chef
  def do_something
    @r[e]cipe  # Guessed Type: Recipe
  end

  def prepare_recipe
    @recipe = Recipe.new
  end
end

class Recipe
end
```

### top-level variable

```ruby
x = 42
[x]  # Guessed Type: Integer
```

### singleton class scope

```ruby
class Foo
  class << self
    def bar
      x = "singleton"
      [x]  # Guessed Type: String
    end
  end
end
```

## Block parameter references

### tap block parameter referenced in keyword argument

```ruby
module RBS
  class Environment2
    def self.from_loader(loader)
      self.new.tap do |env|
        loader.load(env: [e]nv)  # Guessed Type: RBS::Environment2
      end
    end
  end
end
```

### block parameter referenced in regular method argument

```ruby
class User
  def self.build
    self.new.tap do |user|
      validate([u]ser)  # Guessed Type: User
    end
  end
end
```

