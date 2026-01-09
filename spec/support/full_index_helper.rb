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
      return unless @server

      @server.run_shutdown
      @server = nil
    rescue StandardError
      @server = nil
    end

    private

    def create_server_with_cached_index
      start_time = Time.now

      if cache_valid?
        server = create_server_from_cache
        elapsed = (Time.now - start_time).round(2)
        warn "[FullIndexHelper] Loaded from cache in #{elapsed}s"
      else
        server = create_fully_indexed_server
        save_cache(server.global_state.index)
        elapsed = (Time.now - start_time).round(2)
        warn "[FullIndexHelper] Full indexing complete in #{elapsed}s (cache saved)"
      end

      server
    end

    def create_server_from_cache
      server = RubyLsp::Server.new(test_mode: true)

      # Load cached index
      cached_index = load_cache

      # Replace the server's index with cached one
      server.global_state.instance_variable_set(:@index, cached_index)

      server
    end

    def create_fully_indexed_server
      warn "[FullIndexHelper] Creating fully-indexed server..."

      server = RubyLsp::Server.new(test_mode: false)

      # Send LSP initialize request to trigger full indexing
      server.process_message({
                               id: 1,
                               method: "initialize",
                               params: { capabilities: {} }
                             })
      server.process_message({ method: "initialized" })

      # Wait for indexing to complete (max 120 seconds)
      timeout = Time.now + 120
      sleep 0.1 until server.global_state.index.initial_indexing_completed || Time.now > timeout

      raise "Indexing timeout: RubyIndexer did not complete initial indexing within 120 seconds" unless server.global_state.index.initial_indexing_completed

      server
    end

    # Cache management

    def cache_valid?
      return false unless File.exist?(cache_file)
      return false unless File.exist?(cache_key_file)

      stored_key = File.read(cache_key_file).strip
      stored_key == current_cache_key
    end

    def current_cache_key
      lockfile = File.join(Dir.pwd, "Gemfile.lock")
      return "" unless File.exist?(lockfile)

      Digest::SHA256.hexdigest(File.read(lockfile))
    end

    def cache_file
      File.join(CACHE_DIR, "index.marshal")
    end

    def cache_key_file
      File.join(CACHE_DIR, "cache_key")
    end

    def save_cache(index)
      FileUtils.mkdir_p(CACHE_DIR)

      # Save the index
      File.binwrite(cache_file, Marshal.dump(index))

      # Save the cache key
      File.write(cache_key_file, current_cache_key)
    end

    def load_cache
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
    # Always pre-warm the shared server for integration tests
    FullIndexHelper.server
  end

  config.after(:suite) do
    FullIndexHelper.reset! if FullIndexHelper.initialized?
  end
end
