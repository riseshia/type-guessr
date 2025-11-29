# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
require "ruby_lsp/test_helper"
require "uri"

# Ensure TypeInferrer is loaded for tests
require "type_guessr/core/type_inferrer"

require "minitest/autorun"

# Enable debug mode for tests
ENV["TYPE_GUESSR_DEBUG"] = "1"
