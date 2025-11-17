# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
require "ruby_lsp/test_helper"
require "uri"

require "minitest/autorun"

# Enable debug mode for tests
ENV["TYPE_GUESSR_DEBUG"] = "1"
