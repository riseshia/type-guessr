# frozen_string_literal: true

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end
end

# Load core components
require_relative "type_guessr/version"
require_relative "type_guessr/core/scope_resolver"
require_relative "type_guessr/core/chain_index"
require_relative "type_guessr/core/chain_extractor"

# Load Ruby LSP integration
require_relative "ruby_lsp/type_guessr/index_adapter"
require_relative "ruby_lsp/type_guessr/type_matcher"
require_relative "ruby_lsp/type_guessr/chain_resolver"
require_relative "ruby_lsp/type_guessr/hover"
require_relative "ruby_lsp/type_guessr/addon"

# Backward compatibility: Create aliases in old namespace
module RubyLsp
  module TypeGuessr
    # Version
    VERSION = ::TypeGuessr::VERSION

    # Core components
    ScopeResolver = ::TypeGuessr::Core::ScopeResolver
    ChainIndex = ::TypeGuessr::Core::ChainIndex
    ChainExtractor = ::TypeGuessr::Core::ChainExtractor
  end
end
