# RubyLsp::Guesser

A Ruby LSP addon that provides hover tooltips with helpful information.

## Features

- **Type Inference**: Automatically infers variable types based on method call patterns
- **Hover Tooltips**: Shows inferred types when hovering over variables
- **Heuristic Approach**: Works without type annotations by analyzing method usage
- **Smart Matching**: Finds classes that have all the methods called on a variable

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby-lsp-guesser'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby-lsp-guesser
```

## Usage

Once installed, the addon will automatically be loaded by Ruby LSP. Hover over variables, parameters, or instance variables to see inferred types.

### Example

```ruby
class Recipe
  def ingredients
    []
  end

  def steps
    []
  end
end

def process(recipe)
  recipe.ingredients  # Hover over 'recipe' shows: Inferred type: Recipe
  recipe.steps
end
```

The addon analyzes method calls (`ingredients`, `steps`) and finds that only the `Recipe` class has both methods, so it infers the type as `Recipe`.

### Debug Mode

Enable debug mode to see method call information in the LSP output. There are two ways:

**Method 1: Config file (recommended)**

Create a `.type-guessr.yml` file in your project root:

```yaml
debug: true
```

Then restart Ruby LSP (VSCode: reload window).

**Method 2: Environment variable**

Launch VSCode from terminal with the environment variable:

```bash
export TYPE_GUESSR_DEBUG=1
code .
```

In debug mode, the addon will log method calls to stderr and show method lists in hover tooltips when type cannot be inferred.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ruby-lsp-guesser.
