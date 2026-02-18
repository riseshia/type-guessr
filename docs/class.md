# Class Type Inference

This document is auto-generated from tests tagged with `:doc`.

> `[x]` marks the cursor position where hover was triggered.

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

## .new hover with initialize parameters

### when class has initialize with required params

```ruby
class Recipe
  def initialize(a, b)
  end
end

Recipe.[n]ew(1, 2)  # Signature: (untyped a, untyped b) -> Recipe
```

### when class has no initialize

```ruby
class Empty
end

Empty.[n]ew  # Signature: () -> Empty
```

### when class has initialize with optional params

```ruby
class Config
  def initialize(host, port = 8080)
  end
end

Config.[n]ew("localhost")  # Signature: (untyped host, ?Integer port) -> Config
```

### self.new in singleton method

```ruby
class User
  def self.create
    self.[n]ew  # Signature: () -> User
  end
end
```

### self.new with initialize params in singleton method

```ruby
class User
  def initialize(name, age)
  end

  def self.create(name, age)
    self.[n]ew(name, age)  # Signature: (untyped name, untyped age) -> User
  end
end
```

### when calling .new with short constant name in nested module

```ruby
module Outer
  class Inner
    def initialize(arg1, arg2 = nil)
    end
  end

  class User
    def create
      Inner.[n]ew("test")  # Signature: (untyped arg1, ?nil arg2) -> Outer::Inner
    end
  end
end
```

### when calling .new with deeply nested short constant name

```ruby
module A
  module B
    class Target
      def initialize(x, y, z = 0)
      end
    end

    class Consumer
      def build
        Target.[n]ew(1, 2)  # Signature: (untyped x, untyped y, ?Integer z) -> A::B::Target
      end
    end
  end
end
```

## Class instantiation (misc)

### basic class instantiation

```ruby
class C
  def initialize(n)
    n
  end

  def foo(n)
    C
  end
end

C.new(1).foo("str")
[i]nstance = C.new(1)  # Guessed Type: C
```

### class reference in method

```ruby
class C
  def foo(n)
    C
  end
end

[k]lass = C.new(1).foo("str")  # Guessed Type: singleton(C)
```

### nested class

```ruby
class C
  class D
    def foo(n)
      C
    end
  end
end

[k]lass = C::D.new.foo("str")  # Guessed Type: singleton(C)
```

## Initialize method

### initialize with instance variable

```ruby
class A
end

class B
  def initialize(xxx)
    @xxx = xxx
  end
end

class C
end

def foo
  B.new(1)
end

[i]nstance = foo  # Guessed Type: B
```

## Module inclusion

### module method call

```ruby
module M
  def foo
    42
  end
end

class C
  include M
  def bar
    foo
  end
end

[r]esult = C.new.bar  # Guessed Type: Integer
```

## Module extend

### class method from extended module

```ruby
module M
  def foo
    42
  end
end

class C
  extend M
end

[r]esult = C.foo  # Guessed Type: Integer
```

## Class method calls (ClassName.method)

### stdlib class method signature

```ruby
result = File.[e]xist?("test.txt")  # Signature: (::string | ::_ToPath | ::IO file_name) -> bool
result
```

### gem class method signature

```ruby
loader = RBS::EnvironmentLoader.new
env = RBS::Environment.[f]rom_loader(loader)  # Signature: (RBS::EnvironmentLoader loader) -> untyped
env
```

## Instance method calls (receiver.method)

### gem instance method signature

```ruby
loader = RBS::EnvironmentLoader.new
env = RBS::Environment.from_loader(loader)
resolved = env.[r]esolve_type_names  # Signature: (?only: untyped) -> untyped
resolved
```

