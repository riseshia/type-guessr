# frozen_string_literal: true

require_relative "ruby_lsp/ruby_lsp_guesser/version"
require_relative "ruby_lsp/ruby_lsp_guesser/scope_resolver"
require_relative "ruby_lsp/ruby_lsp_guesser/parameter"
require_relative "ruby_lsp/ruby_lsp_guesser/method_signature"
require_relative "ruby_lsp/ruby_lsp_guesser/method_signature_index"
require_relative "ruby_lsp/ruby_lsp_guesser/rbs_signature_indexer"
require_relative "ruby_lsp/ruby_lsp_guesser/type_matcher"
require_relative "ruby_lsp/ruby_lsp_guesser/hover"
require_relative "ruby_lsp/ruby_lsp_guesser/addon"

module RubyLsp
  module Guesser
    class Error < StandardError; end
  end
end
