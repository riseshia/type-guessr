# Type-Guessr Architecture Refactoring Plan

## Goal
Refactor the gem architecture to separate core type inference functionality from Ruby LSP integration, making the core library usable independently.

## Architecture Overview

```
┌─────────────────────────────────────┐
│    Integrations Layer (Optional)    │
│  - Ruby LSP Addon                   │
│  - CLI Tool (Future)                │
│  - Rails Integration (Future)       │
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│       Core Layer (Independent)      │
│  - TypeResolver                     │
│  - TypeMatcher                      │
│  - VariableIndex                    │
│  - MethodSignatureIndex             │
│  - RBSIndexer                       │
│  - ASTAnalyzer                      │
└─────────────────────────────────────┘
```

## Tasks

### Phase 1: Create Core Module Structure and Move Independent Components
- [x] Create directory structure
  - [x] `lib/type_guessr/core/`
  - [x] `lib/type_guessr/core/models/`
  - [x] `lib/type_guessr/integrations/ruby_lsp/`

- [x] Move data models (no dependencies)
  - [x] `parameter.rb` → `core/models/parameter.rb`
    - Change namespace: `RubyLsp::TypeGuessr::Parameter` → `TypeGuessr::Core::Parameter`
  - [x] `method_signature.rb` → `core/models/method_signature.rb`
    - Change namespace: `RubyLsp::TypeGuessr::MethodSignature` → `TypeGuessr::Core::MethodSignature`

- [x] Move independent index components
  - [x] `method_signature_index.rb` → `core/method_signature_index.rb`
    - Change namespace: `RubyLsp::TypeGuessr::MethodSignatureIndex` → `TypeGuessr::Core::MethodSignatureIndex`
    - Update MethodSignature references
  - [x] `variable_index.rb` → `core/variable_index.rb`
    - Change namespace: `RubyLsp::TypeGuessr::VariableIndex` → `TypeGuessr::Core::VariableIndex`
  - [x] `scope_resolver.rb` → `core/scope_resolver.rb`
    - Change namespace: `RubyLsp::TypeGuessr::ScopeResolver` → `TypeGuessr::Core::ScopeResolver`

- [x] Move RBS indexer
  - [x] `rbs_signature_indexer.rb` → `core/rbs_indexer.rb`
    - Rename: `RBSSignatureIndexer` → `RBSIndexer`
    - Change namespace: `RubyLsp::TypeGuessr::RBSIndexer` → `TypeGuessr::Core::RBSIndexer`
    - Update MethodSignatureIndex references

- [x] Move AST analyzer
  - [x] `ast_visitor.rb` → `core/ast_analyzer.rb`
    - Rename: `ASTVisitor` → `ASTAnalyzer` (more descriptive name)
    - Change namespace: `RubyLsp::TypeGuessr::ASTAnalyzer` → `TypeGuessr::Core::ASTAnalyzer`
    - Update VariableIndex, ScopeResolver references

- [x] Update main entry point
  - [x] Update `lib/type-guessr.rb` to load new structure

### Phase 2: Separate Ruby LSP Integration Layer
- [x] Refactor TypeMatcher
  - [x] Split into two parts:
    - [x] Core logic → `core/type_matcher.rb` (interface-based, no LSP dependency)
    - [x] LSP adapter → `integrations/ruby_lsp/index_adapter.rb`
  - [x] Change namespace: `RubyLsp::TypeGuessr::TypeMatcher` → `TypeGuessr::Core::TypeMatcher`

- [x] Refactor VariableTypeResolver
  - [x] Core logic → `core/type_resolver.rb`
  - [x] Remove LSP dependencies (node_context)
  - [x] Change to pure functional interface
  - [x] Change namespace: `RubyLsp::TypeGuessr::TypeResolver` → `TypeGuessr::Core::TypeResolver`

- [x] Move LSP integration components
  - [x] `addon.rb` → `integrations/ruby_lsp/addon.rb`
    - Change namespace: `RubyLsp::TypeGuessr::Addon` → `TypeGuessr::Integrations::RubyLsp::Addon`
    - Update to use core API
  - [x] `hover.rb` → `integrations/ruby_lsp/hover_provider.rb`
    - Rename: `Hover` → `HoverProvider`
    - Change namespace: `RubyLsp::TypeGuessr::HoverProvider` → `TypeGuessr::Integrations::RubyLsp::HoverProvider`
  - [x] `hover_content_builder.rb` → `integrations/ruby_lsp/hover_content_builder.rb`
    - Change namespace: `RubyLsp::TypeGuessr::HoverContentBuilder` → `TypeGuessr::Integrations::RubyLsp::HoverContentBuilder`
  - [x] `ruby_index_adapter.rb` → `integrations/ruby_lsp/index_adapter.rb`
    - Change namespace: `RubyLsp::TypeGuessr::RubyIndexAdapter` → `TypeGuessr::Integrations::RubyLsp::IndexAdapter`
  - [x] `variable_type_resolver.rb` → `integrations/ruby_lsp/variable_type_resolver.rb`
    - Change namespace: `RubyLsp::TypeGuessr::VariableTypeResolver` → `TypeGuessr::Integrations::RubyLsp::VariableTypeResolver`
  - [x] `type_matcher.rb` → `integrations/ruby_lsp/type_matcher.rb` (wrapper)
    - Change namespace: `RubyLsp::TypeGuessr::TypeMatcher` → `TypeGuessr::Integrations::RubyLsp::TypeMatcher`

- [x] Update Addon to use core API
  - [x] Use `TypeGuessr::Core::RBSIndexer`
  - [x] Use `TypeGuessr::Core::ASTAnalyzer`

### Phase 3: Create Main TypeGuessr API and Facade
- [ ] Create main module API
  - [ ] Add `TypeGuessr.analyze_file(file_path)` method
  - [ ] Add `TypeGuessr.create_project(root_path)` method

- [ ] Create Project class
  - [ ] `lib/type_guessr/project.rb`
  - [ ] Project-wide indexing management
  - [ ] RBS indexing
  - [ ] AST analysis
  - [ ] Type inference API

- [ ] Create FileAnalyzer
  - [ ] `lib/type_guessr/core/file_analyzer.rb`
  - [ ] Single file analysis functionality
  - [ ] Can run independently

### Phase 4: Update Tests to Match New Structure
- [ ] Separate core tests
  - [ ] Create `test/type_guessr/core/` directory
  - [ ] Move and update core component tests:
    - [ ] `test_type_matcher.rb` → `test/type_guessr/core/test_type_matcher.rb`
    - [ ] `test_variable_index.rb` → `test/type_guessr/core/test_variable_index.rb`
    - [ ] `test_scope_resolver.rb` → `test/type_guessr/core/test_scope_resolver.rb`
    - [ ] `test_method_signature.rb` → `test/type_guessr/core/test_method_signature.rb`
    - [ ] `test_method_signature_index.rb` → `test/type_guessr/core/test_method_signature_index.rb`
    - [ ] `test_parameter.rb` → `test/type_guessr/core/test_parameter.rb`
    - [ ] `test_rbs_signature_indexer.rb` → `test/type_guessr/core/test_rbs_indexer.rb`
    - [ ] `test_ast_visitor.rb` → `test/type_guessr/core/test_ast_analyzer.rb`

- [ ] Separate integration tests
  - [ ] Create `test/type_guessr/integrations/ruby_lsp/` directory
  - [ ] Move LSP-related tests:
    - [ ] `test_hover.rb` → `test/type_guessr/integrations/ruby_lsp/test_hover_provider.rb`
    - [ ] `test_guesser.rb` → reorganize as integration test

- [ ] Add new API tests
  - [ ] `test/test_type_guessr.rb`: main API tests
  - [ ] `test/type_guessr/test_project.rb`: Project class tests

- [ ] Run all tests and fix issues
  - [ ] `rake test`
  - [ ] Fix any failures

### Phase 5: Update Documentation and Configuration
- [ ] Update README.md
  - [ ] Update project description (Ruby LSP addon + independent library)
  - [ ] Add usage sections:
    - [ ] Using as core library
    - [ ] Using as Ruby LSP addon
  - [ ] Add architecture diagram

- [ ] Update CLAUDE.md
  - [ ] Reflect new project structure
  - [ ] Explain responsibilities per layer
  - [ ] Update development guidelines

- [ ] Clean up configuration files
  - [ ] Rename `.ruby-lsp-guesser.yml.example` → `.type-guessr.yml.example`
  - [ ] Review RuboCop configuration

- [ ] Create CHANGELOG.md
  - [ ] Document v0.2.0 changes
  - [ ] Note breaking changes
  - [ ] Provide migration guide

## Expected File Structure After Refactoring

```
lib/
├── type-guessr.rb                              # Main entry point
├── type_guessr/
│   ├── version.rb
│   ├── project.rb                              # Project-wide API
│   │
│   ├── core/                                   # Core functionality (independent)
│   │   ├── type_resolver.rb                    # Type inference engine
│   │   ├── type_matcher.rb                     # Method-based type matching
│   │   ├── variable_index.rb                   # Variable information storage
│   │   ├── method_signature_index.rb           # Method signature storage
│   │   ├── rbs_indexer.rb                      # RBS file indexing
│   │   ├── ast_analyzer.rb                     # AST analysis (Prism)
│   │   ├── scope_resolver.rb                   # Scope analysis
│   │   ├── file_analyzer.rb                    # Single file analysis
│   │   └── models/                             # Data models
│   │       ├── method_signature.rb
│   │       └── parameter.rb
│   │
│   └── integrations/                           # Integration features (optional)
│       └── ruby_lsp/                           # Ruby LSP addon
│           ├── addon.rb                        # LSP addon registration
│           ├── hover_provider.rb               # Hover functionality
│           ├── hover_content_builder.rb        # Hover content formatting
│           └── index_adapter.rb                # RubyIndexer adapter
```

## Notes

- **No Backward Compatibility**: This is pre-release, no need to maintain compatibility
- **Atomic Commits**: Each phase should be one atomic commit
- **Test-First**: Run tests after each phase completion
- **Linter**: Run RuboCop before committing
