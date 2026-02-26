[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/riseshia/type-guessr)

# TypeGuessr

> **Warning**: This project is under active development. Breaking changes may occur without notice.
>
> CHANGELOG will be maintained once the project reaches a stable phase. Until then, please refer to the commit history.

A Ruby LSP addon that provides heuristic type inference to enhance IDE features like Hover and Go to Definition.

## Features

- **Type Inference**: Automatically infers variable types based on method call patterns
- **Hover Tooltips**: Shows guessed types when hovering over variables
- **Heuristic Approach**: Works without type annotations by analyzing method usage
- **Smart Matching**: Finds classes that have all the methods called on a variable

## Installation

TypeGuessr is a Ruby LSP addon. Add it to your project's Gemfile under the development group:

```ruby
group :development do
  gem 'type-guessr', require: false
end
```

Then run:

```bash
bundle install
```

After installation, restart your editor or reload the Ruby LSP server to activate the addon.

## Usage

Once installed, the addon will automatically be loaded by Ruby LSP. Hover over variables, parameters, or instance variables to see guessed types.

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
  recipe.ingredients  # Hover over 'recipe' shows: Guessed type: Recipe
  recipe.steps
end
```

The addon analyzes method calls (`ingredients`, `steps`) and finds that only the `Recipe` class has both methods, so it infers the type as `Recipe`.

## Configuration

Create a `.type-guessr.yml` file in your project root to customize behavior. See [.type-guessr.yml.example](.type-guessr.yml.example) for all available options.

After changing configuration, restart Ruby LSP (VSCode: reload window).

### Debug Mode

When `debug: true`, the addon will:
- Log debug information to stderr
- Show inference basis in hover tooltips
- Start a debug web server (unless `debug_server: false`)

### Debug Web Server

When enabled, a web server starts at `http://127.0.0.1:<port>` (default port: 7010). This provides a web interface to inspect the type inference:

- **Search**: Search for methods to visualize their IR dependency graphs
- **Graph Visualization**: Interactive dependency graph

This is useful for understanding how TypeGuessr analyzes your codebase and debugging type inference issues.

## MCP Server

TypeGuessr can run as a standalone [MCP](https://modelcontextprotocol.io/) server, exposing its type inference engine to AI tools like Claude Code.

### Setup

Using Claude Code CLI:

```bash
claude mcp add type-guessr -- bundle exec type-guessr mcp
```

Or add to your project's `.mcp.json` manually:

```json
{
  "mcpServers": {
    "type-guessr": {
      "command": "bundle",
      "args": ["exec", "type-guessr", "mcp"]
    }
  }
}
```

Or run directly:

```bash
bundle exec type-guessr mcp [project_path]
```

If `project_path` is omitted, the current directory is used.

### Available Tools

| Tool | Description |
|------|-------------|
| `infer_type` | Infer the type at a specific file/line/column |
| `get_method_signature` | Get the inferred signature of a method |
| `search_methods` | Search for method definitions by name or pattern |

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/riseshia/type-guessr.
