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
require_relative "ruby_lsp/type_guessr/type_matcher"
require_relative "ruby_lsp/type_guessr/hover"
require_relative "ruby_lsp/type_guessr/addon"

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
  end
end
