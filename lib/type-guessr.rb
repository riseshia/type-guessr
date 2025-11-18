# frozen_string_literal: true

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end
end

# Load core components
require_relative "type_guessr/version"
require_relative "type_guessr/core/scope_resolver"
require_relative "type_guessr/core/models/parameter"
require_relative "type_guessr/core/models/method_signature"
require_relative "type_guessr/core/method_signature_index"
require_relative "type_guessr/core/rbs_indexer"
require_relative "type_guessr/core/variable_index"
require_relative "type_guessr/core/ast_analyzer"
require_relative "type_guessr/core/type_matcher"
require_relative "type_guessr/core/type_resolver"

# Load Ruby LSP integration
require_relative "type_guessr/integrations/ruby_lsp/index_adapter"
require_relative "type_guessr/integrations/ruby_lsp/type_matcher"
require_relative "type_guessr/integrations/ruby_lsp/variable_type_resolver"
require_relative "type_guessr/integrations/ruby_lsp/hover_content_builder"
require_relative "type_guessr/integrations/ruby_lsp/hover_provider"
require_relative "type_guessr/integrations/ruby_lsp/addon"

# Backward compatibility: Create aliases in old namespace
module RubyLsp
  module TypeGuessr
    # Version
    VERSION = ::TypeGuessr::VERSION

    # Core models
    Parameter = ::TypeGuessr::Core::Parameter
    MethodSignature = ::TypeGuessr::Core::MethodSignature

    # Core components
    ScopeResolver = ::TypeGuessr::Core::ScopeResolver
    MethodSignatureIndex = ::TypeGuessr::Core::MethodSignatureIndex
    VariableIndex = ::TypeGuessr::Core::VariableIndex
    RBSSignatureIndexer = ::TypeGuessr::Core::RBSIndexer
    ASTVisitor = ::TypeGuessr::Core::ASTAnalyzer

    # Integration components (for backward compatibility)
    RubyIndexAdapter = ::TypeGuessr::Integrations::RubyLsp::IndexAdapter
    TypeMatcher = ::TypeGuessr::Integrations::RubyLsp::TypeMatcher
    VariableTypeResolver = ::TypeGuessr::Integrations::RubyLsp::VariableTypeResolver
    HoverContentBuilder = ::TypeGuessr::Integrations::RubyLsp::HoverContentBuilder
    Hover = ::TypeGuessr::Integrations::RubyLsp::HoverProvider
    Addon = ::TypeGuessr::Integrations::RubyLsp::Addon
  end
end
