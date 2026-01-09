# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
# Load addon for integration tests (normally auto-discovered by Ruby LSP)
require "ruby_lsp/type_guessr/addon"
require "ruby_lsp/test_helper"
require "uri"

# Load doc collector for generating documentation from tests
require_relative "support/doc_collector"

# Load full index helper for tests that need gem/stdlib method definitions
require_relative "support/full_index_helper"

RSpec.configure do |config|
  # Disable debug logging and server for all tests
  config.before do
    allow(RubyLsp::TypeGuessr::Config).to receive_messages(debug?: false, debug_server_enabled?: false)
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order to surface order dependencies
  # But use defined order when generating docs for consistency
  config.order = ENV["GENERATE_DOCS"] ? :defined : :random

  # Seed global randomization in this process using the `--seed` CLI option
  Kernel.srand config.seed
end

# Test helper module for TypeGuessr addon tests
module TypeGuessrTestHelper
  include RubyLsp::TestHelper

  # Custom helper that uses a shared, fully-indexed server for all integration tests.
  # The server is initialized once per test suite and reused, with caching for fast subsequent runs.
  # This provides access to gem/stdlib method definitions while maintaining good performance.
  #
  # Uses a fixed URI (source.rb) so that handle_change properly invalidates RubyIndexer's
  # ancestor cache when class definitions change between tests.
  def with_server_and_addon(source, &block)
    server = FullIndexHelper.server
    uri = URI("file://#{Dir.pwd}/source.rb")

    # Open the document in the server (required for hover/other LSP requests)
    server.process_message({
                             method: "textDocument/didOpen",
                             params: {
                               textDocument: {
                                 uri: uri,
                                 text: source,
                                 version: 1,
                                 languageId: "ruby"
                               }
                             }
                           })

    # Manually activate only the TypeGuessr addon
    addon = RubyLsp::TypeGuessr::Addon.new
    addon.activate(server.global_state, server.instance_variable_get(:@outgoing_queue))

    # Register the addon so the server knows about it
    RubyLsp::Addon.addons << addon

    # Index the source directly for integration tests
    addon.runtime_adapter.index_source(uri.to_s, source)

    # Use handle_change for proper ancestor cache invalidation
    server.global_state.index.handle_change(uri, source)

    begin
      block.call(server, uri)
    ensure
      addon.deactivate
      RubyLsp::Addon.addons.delete(addon)
      # Close the document
      server.process_message({
                               method: "textDocument/didClose",
                               params: { textDocument: { uri: uri } }
                             })
    end
  end
end
