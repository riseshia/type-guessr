# frozen_string_literal: true

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end
end

# Load version
require_relative "type_guessr/version"

# Load core components
require_relative "type_guessr/core"

# Load Ruby LSP integration
# NOTE: addon.rb is NOT required here - it's auto-discovered by Ruby LSP
# Requiring it here would cause double activation
require_relative "ruby_lsp/type_guessr/constants"
require_relative "ruby_lsp/type_guessr/runtime_adapter"
require_relative "ruby_lsp/type_guessr/hover"
require_relative "ruby_lsp/type_guessr/debug_server"
