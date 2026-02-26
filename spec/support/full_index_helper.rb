# frozen_string_literal: true

require "digest"
require "fileutils"

# Provides a shared, fully-indexed Ruby LSP server for integration tests.
# Uses Gemfile.lock as cache key to avoid re-indexing on every test run.
#
# Cache behavior:
# - First run: Full indexing (~5-20s), then saves cache
# - Subsequent runs: Loads from cache (~1-2s)
# - Cache invalidation: Automatic when Gemfile.lock changes
#
# Usage:
# - All integration tests automatically use full indexing via `with_server_and_addon`
# - Cache is stored in tmp/test_index_cache/
module FullIndexHelper
  CACHE_DIR = File.expand_path("../../tmp/test_index_cache", __dir__)

  class << self
    def server
      @server ||= create_server_with_cached_index
    end

    def addon
      @addon ||= create_addon
    end

    def runtime_adapter
      addon.runtime_adapter
    end

    def global_state
      server.global_state
    end

    def index
      global_state.index
    end

    def initialized?
      !@server.nil?
    end

    def reset!
      if @addon
        @addon.deactivate
        RubyLsp::Addon.addons.delete(@addon)
        @addon = nil
      end

      return unless @server

      @server.run_shutdown
      @server = nil
    rescue StandardError
      @addon = nil
      @server = nil
    end

    private def create_addon
      addon = RubyLsp::TypeGuessr::Addon.new
      addon.activate(server.global_state, server.instance_variable_get(:@outgoing_queue))
      RubyLsp::Addon.addons << addon

      # Wait for start_indexing thread to complete
      sleep 0.1 until addon.runtime_adapter&.indexing_completed?

      addon
    end

    private def create_server_with_cached_index
      if cache_valid?
        create_server_from_cache
      else
        server = create_fully_indexed_server
        save_cache(server.global_state.index)
        server
      end
    end

    private def create_server_from_cache
      server = RubyLsp::Server.new(test_mode: true)

      # Load cached index
      cached_index = load_cache

      # Replace the server's index with cached one
      server.global_state.instance_variable_set(:@index, cached_index)

      server
    end

    private def create_fully_indexed_server
      # Use test_mode: true to prevent the outgoing_dispatcher from writing JSON-RPC
      # to stdout (which pollutes test output) and from competing with pop_response
      # for messages in the outgoing_queue (which causes flaky test failures).
      server = RubyLsp::Server.new(test_mode: true)

      # Send LSP initialize request to trigger full indexing
      server.process_message({
                               id: 1,
                               method: "initialize",
                               params: { capabilities: {} }
                             })

      # Track threads before "initialized" triggers perform_initial_indexing in a background thread
      threads_before = Thread.list

      server.process_message({ method: "initialized" })

      # Wait for indexing to complete (max 120 seconds)
      timeout = Time.now + 120
      sleep 0.1 until server.global_state.index.initial_indexing_completed || Time.now > timeout

      raise "Indexing timeout: RubyIndexer did not complete initial indexing within 120 seconds" unless server.global_state.index.initial_indexing_completed

      # Wait for the indexing thread to fully finish post-processing (GC.compact, clear_ancestors, etc.)
      # Without this, Ruby 4.0 raises "can't add a new key into hash during iteration" when tests
      # call handle_change while the background thread still holds an iteration on @entries.
      (Thread.list - threads_before).each { |t| t.join(30) }

      # Drain initialization messages from the outgoing_queue so that pop_response
      # in tests reads the correct (hover/completion) response, not a stale init message.
      # In test_mode the outgoing_dispatcher is inactive, so these would otherwise pile up.
      queue = server.instance_variable_get(:@outgoing_queue)
      queue.pop until queue.empty?

      server
    end

    # Cache management

    private def cache_valid?
      return false unless File.exist?(cache_file)
      return false unless File.exist?(cache_key_file)

      stored_key = File.read(cache_key_file).strip
      stored_key == current_cache_key
    end

    private def current_cache_key
      lockfile = File.join(Dir.pwd, "Gemfile.lock")
      return "" unless File.exist?(lockfile)

      Digest::SHA256.hexdigest(File.read(lockfile))
    end

    private def cache_file
      File.join(CACHE_DIR, "index.marshal")
    end

    private def cache_key_file
      File.join(CACHE_DIR, "cache_key")
    end

    private def save_cache(index)
      FileUtils.mkdir_p(CACHE_DIR)

      # Save the index
      File.binwrite(cache_file, Marshal.dump(index))

      # Save the cache key
      File.write(cache_key_file, current_cache_key)
    end

    private def load_cache
      # rubocop:disable Security/MarshalLoad
      # Safe: Loading our own cache file, validated by cache key check
      Marshal.load(File.binread(cache_file))
      # rubocop:enable Security/MarshalLoad
    end
  end
end

# RSpec configuration for full index tests
RSpec.configure do |config|
  config.before(:suite) do
    # Disable background gem indexing for all tests — opt in where needed
    RubyLsp::TypeGuessr::Config.instance_variable_set(
      :@cached_config,
      { "enabled" => true, "debug" => false, "background_gem_indexing" => false }
    )

    # Only initialize server and addon when ruby_lsp/internal is loaded (integration tests)
    if defined?(RubyLsp::Server)
      FullIndexHelper.server
      FullIndexHelper.addon
    end
  end

  config.after(:suite) do
    FullIndexHelper.reset! if FullIndexHelper.initialized?
    RubyLsp::TypeGuessr::Config.reset!
  end
end
