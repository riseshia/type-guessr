# frozen_string_literal: true

require_relative "ruby_lsp/type_guessr/version"
require_relative "ruby_lsp/type_guessr/scope_resolver"
require_relative "ruby_lsp/type_guessr/parameter"
require_relative "ruby_lsp/type_guessr/method_signature"
require_relative "ruby_lsp/type_guessr/method_signature_index"
require_relative "ruby_lsp/type_guessr/rbs_signature_indexer"
require_relative "ruby_lsp/type_guessr/type_matcher"
require_relative "ruby_lsp/type_guessr/hover"
require_relative "ruby_lsp/type_guessr/addon"

module RubyLsp
  module TypeGuessr
    class Error < StandardError; end
  end
end
