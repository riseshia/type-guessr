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

# Test helper module for TypeGuessr addon tests
module TypeGuessrTestHelper
  include RubyLsp::TestHelper

  # Custom helper that skips loading all addons (especially RuboCop which is slow)
  # and only activates the TypeGuessr addon we're testing.
  # This improves test performance significantly (~40x faster).
  def with_server_and_addon(source, &block)
    with_server(source, stub_no_typechecker: true, load_addons: false) do |server, uri|
      # Manually activate only the TypeGuessr addon
      addon = RubyLsp::TypeGuessr::Addon.new
      addon.activate(server.global_state, server.instance_variable_get(:@outgoing_queue))

      # Register the addon so the server knows about it
      RubyLsp::Addon.addons << addon

      begin
        block.call(server, uri)
      ensure
        addon.deactivate
        RubyLsp::Addon.addons.delete(addon)
      end
    end
  end
end
