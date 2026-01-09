# frozen_string_literal: true

# Main module for TypeGuessr
module TypeGuessr
  class Error < StandardError; end
end

# Load version
require_relative "type_guessr/version"

# Load core components (IR-based architecture)
require_relative "type_guessr/core/types"
require_relative "type_guessr/core/ir/nodes"
require_relative "type_guessr/core/index/location_index"
require_relative "type_guessr/core/converter/prism_converter"
require_relative "type_guessr/core/converter/rbs_converter"
require_relative "type_guessr/core/inference/result"
require_relative "type_guessr/core/inference/resolver"
require_relative "type_guessr/core/rbs_provider"
require_relative "type_guessr/core/logger"

# Load Ruby LSP integration
# NOTE: addon.rb is NOT required here - it's auto-discovered by Ruby LSP
# Requiring it here would cause double activation
require_relative "ruby_lsp/type_guessr/config"
require_relative "ruby_lsp/type_guessr/runtime_adapter"
require_relative "ruby_lsp/type_guessr/hover"
require_relative "ruby_lsp/type_guessr/debug_server"
