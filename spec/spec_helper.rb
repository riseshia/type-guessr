# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "type-guessr"
# Load addon for integration tests (normally auto-discovered by Ruby LSP)
require "ruby_lsp/type_guessr/addon"
require "ruby_lsp/test_helper"
require "uri"

# Load all support files dynamically
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  # Preload RBS signatures once before all tests
  config.before(:suite) do
    TypeGuessr::Core::Registry::SignatureRegistry.instance.preload

    # Start E2E server if E2E tests are being run
    SharedLspServer.instance if config.filter.rules[:e2e] || ARGV.any? { |arg| arg.include?("e2e") }
  end

  config.after(:suite) do
    SharedLspServer.shutdown!
  end

  # Disable debug logging and server for all tests
  config.before do
    allow(RubyLsp::TypeGuessr::Config).to receive_messages(
      debug?: false,
      debug_server_enabled?: false,
      debug_server_port: 7010,
      background_indexing?: false
    )
  end

  # Include E2EHelper for specs tagged with :e2e
  config.include E2EHelper, :e2e

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

  # Helper to perform hover request on source code at given position
  def hover_on_source(source, position)
    with_server_and_addon(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: position }
      )

      result = pop_result(server)
      result.response
    end
  end

  # Shared, fully-indexed server for integration tests. Uses fixed URI (source.rb) so that
  # handle_change properly invalidates RubyIndexer's ancestor cache between tests.
  def with_server_and_addon(source, &block)
    server = FullIndexHelper.server
    uri = URI("file://#{Dir.pwd}/source.rb")

    server.process_message(did_open_message(uri, source))

    addon = RubyLsp::TypeGuessr::Addon.new
    addon.activate(server.global_state, server.instance_variable_get(:@outgoing_queue))
    RubyLsp::Addon.addons << addon

    addon.runtime_adapter&.index_source(uri.to_s, source)
    server.global_state.index.handle_change(uri, source)
    addon.runtime_adapter&.build_member_index!

    begin
      block.call(server, uri)
    ensure
      addon.deactivate
      RubyLsp::Addon.addons.delete(addon)
      server.process_message(did_close_message(uri))
    end
  end

  private def did_open_message(uri, source)
    {
      method: "textDocument/didOpen",
      params: {
        textDocument: { uri: uri, text: source, version: 1, languageId: "ruby" }
      }
    }
  end

  private def did_close_message(uri)
    {
      method: "textDocument/didClose",
      params: { textDocument: { uri: uri } }
    }
  end
end
