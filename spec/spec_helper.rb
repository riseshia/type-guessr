# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
require "ruby_lsp/test_helper"
require "uri"

# Ensure TypeInferrer is loaded for tests
require "ruby_lsp/type_guessr/type_inferrer"

# Enable debug mode for tests (but disable debug server)
ENV["TYPE_GUESSR_DEBUG"] = "1"
ENV["TYPE_GUESSR_DISABLE_DEBUG_SERVER"] = "1"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed
end

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

      # Index the source directly for integration tests
      # This works with in-memory test sources and doesn't require actual files
      addon.runtime_adapter.index_source(uri.to_s, source)

      begin
        block.call(server, uri)
      ensure
        addon.deactivate
        RubyLsp::Addon.addons.delete(addon)
      end
    end
  end
end
