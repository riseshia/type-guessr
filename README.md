[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/riseshia/type-guessr)

# TypeGuessr

> **Warning**: This project is under active development. Breaking changes may occur without notice.

A heuristic type inference CLI for Ruby. Detects potential NoMethodError sites by analyzing method call patterns — no type annotations needed.

## How It Works

TypeGuessr uses **duck-type inference**: if a variable calls methods `foo`, `bar`, and `baz`, it finds all classes that define ALL three methods. If no class matches (zero candidates), that's a potential NoMethodError.

The method index is built at runtime via `ObjectSpace`, so it includes all loaded classes, mixins, and inherited methods — no static analysis gaps.

## Installation

Add to your project's Gemfile:

```ruby
group :development do
  gem 'type-guessr', require: false
end
```

Then run:

```bash
bundle install
```

## Usage

```bash
# Check current project
bundle exec type-guessr check

# Check a specific project
bundle exec type-guessr check --path=/path/to/project

# Rails project (loads full environment)
bundle exec type-guessr check --boot=config/environment.rb

# JSON output for CI/tooling
bundle exec type-guessr check --json
```

### Example Output

```
Found 3 zero-candidate node(s) in 42 project files:

app/services/order_processor.rb:
  L15  ParamNode  payment  [charge, refund, status]

app/models/report.rb:
  L42  LocalVariable  data  [transform, validate, export_csv]
  L78  ParamNode  formatter  [header, body, footer, finalize]
```

Each finding shows a variable/parameter where no class defines ALL the methods called on it.

## Architecture

```
type-guessr check
       │
       ├── Prism AST walker (static call extraction)
       │     Finds: which methods are called on each variable/parameter
       │
       └── Runtime server (subprocess)
             Boots project via Bundler
             Scans ObjectSpace for all loaded modules
             Builds method index: method_name → Set[class_name]
             Serves queries over stdin/stdout JSON IPC
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/riseshia/type-guessr.
