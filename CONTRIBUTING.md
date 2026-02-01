# Contributing to TypeGuessr

Thank you for your interest in contributing to TypeGuessr! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Development Workflow](#development-workflow)
- [Pull Request Process](#pull-request-process)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing Guidelines](#testing-guidelines)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## Getting Started

### Prerequisites

- Ruby 3.3.0 or higher
- Bundler
- Git

### Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/type-guessr.git
   cd type-guessr
   ```
3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/riseshia/type-guessr.git
   ```

## Development Setup

1. Run the setup script to install dependencies:
   ```bash
   bin/setup
   ```

2. Verify everything is working:
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```

3. For an interactive console:
   ```bash
   bin/console
   ```

## Development Workflow

### Before Making Changes

1. Create a new branch from `main`:
   ```bash
   git checkout main
   git pull --ff-only upstream main
   git checkout -b your-feature-branch
   ```

2. Run tests to ensure everything passes:
   ```bash
   bundle exec rspec
   ```

3. Run the linter:
   ```bash
   bundle exec rubocop
   ```

### Making Changes

1. Implement your changes
2. Add or update tests as needed
3. Run tests frequently:
   ```bash
   bundle exec rspec
   ```
4. Check for linting issues:
   ```bash
   bundle exec rubocop
   ```
5. Auto-fix safe linting issues if needed:
   ```bash
   bundle exec rubocop -a
   ```

### Committing Changes

**Important**: Create atomic commits that group related changes together.

✅ **Good**: Single commit with code + tests + linting fixes
```
Add method call tracking for type inference

- Implement AST traversal
- Add test cases
- Fix RuboCop violations
```

❌ **Bad**: Separate commits for the same feature
```
Add method call tracking
Fix rubocop violations
Add tests
```

**Pre-commit checklist**:
1. Run linter on changed files: `bundle exec rubocop <changed_files>`
2. Run all tests: `bundle exec rspec`
3. Check for untracked files: `git status`

## Pull Request Process

1. Ensure all tests pass and there are no linting errors
2. Update documentation if needed (README.md, inline comments)
3. Push your branch to your fork:
   ```bash
   git push origin your-feature-branch
   ```
4. Create a Pull Request on GitHub
5. Fill out the PR template with:
   - Description of changes
   - Related issue (if applicable)
   - Testing performed

### PR Requirements

- All CI checks must pass
- Code must follow the project's style guidelines
- Tests must cover new functionality
- Documentation must be updated if applicable

## Code Style Guidelines

### General

- **Language**: All code, comments, commit messages, and documentation must be in **English**
- Follow [RuboCop](https://rubocop.org/) rules defined in `.rubocop.yml`

## Testing Guidelines

- Use **RSpec** for testing
- Place tests in the `spec/` directory, mirroring the `lib/` structure
- Write descriptive test names that explain the expected behavior
- Test edge cases and error conditions

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/ruby_lsp/hover_spec.rb

# Run tests with verbose output
bundle exec rspec --format documentation
```

## Reporting Issues

### Bug Reports

When reporting bugs, please include:

1. **Description**: Clear description of the issue
2. **Steps to Reproduce**: Minimal steps to reproduce the behavior
3. **Expected Behavior**: What you expected to happen
4. **Actual Behavior**: What actually happened
5. **Environment**:
   - Ruby version (`ruby -v`)
   - RubyLsp version
   - TypeGuessr version
   - OS and version
   - Editor/IDE (if relevant)

### Feature Requests

For feature requests, please include:

1. **Problem**: What problem does this solve?
2. **Proposed Solution**: How would you like it to work?
3. **Alternatives**: Any alternative solutions you've considered
4. **Additional Context**: Any other relevant information

## Project Architecture

TypeGuessr is organized into two main layers:

- **Core** (`lib/type_guessr/core/`): Framework-agnostic type inference logic
- **Integration** (`lib/ruby_lsp/type_guessr/`): Ruby LSP-specific adapter layer

When contributing, consider which layer your changes belong to.

## Questions?

If you have questions, feel free to:
- Open an issue on GitHub
- Check existing issues for similar questions

Thank you for contributing to TypeGuessr! 🎉
