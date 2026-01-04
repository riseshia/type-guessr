# frozen_string_literal: true

require "ruby_lsp/addon"
require_relative "config"
require_relative "runtime_adapter"
require_relative "hover"
require_relative "debug_server"
require_relative "../../type_guessr/core/rbs_provider"

module RubyLsp
  module TypeGuessr
    # TypeGuessr addon for Ruby LSP
    # Provides heuristic type inference without requiring type annotations
    class Addon < ::RubyLsp::Addon
      attr_reader :runtime_adapter

      def name
        "TypeGuessr"
      end

      def activate(global_state, message_queue)
        @global_state = global_state
        @message_queue = message_queue
        @config = Config.new
        @runtime_adapter = RuntimeAdapter.new(global_state)
        @debug_server = nil

        # Preload RBS environment
        ::TypeGuessr::Core::RBSProvider.instance.preload

        # Start debug server if enabled
        start_debug_server if debug_enabled?

        # Index all files on activation
        index_all_files

        message_queue.push(
          method: "window/showMessage",
          params: {
            type: RubyLsp::Constant::MessageType::INFO,
            message: "TypeGuessr activated (IR-based inference)"
          }
        )
      end

      def deactivate
        @debug_server&.stop
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        return unless @config.enabled?

        Hover.new(@runtime_adapter, response_builder, node_context, dispatcher)
      end

      # Handle file changes
      def workspace_did_change_watched_files(changes)
        return unless @config.enabled?

        changes.each do |change|
          uri = URI(change[:uri])
          next unless uri.path&.end_with?(".rb")

          case change[:type]
          when RubyLsp::Constant::FileChangeType::CREATED,
               RubyLsp::Constant::FileChangeType::CHANGED
            reindex_file(uri)
          when RubyLsp::Constant::FileChangeType::DELETED
            file_path = uri.to_standardized_path
            @runtime_adapter.instance_variable_get(:@location_index).remove_file(file_path) if file_path
          end
        end
      end

      private

      def index_all_files
        @global_state.index.indexed_uris.each do |uri|
          reindex_file(uri)
        end
      end

      def reindex_file(uri)
        document = @global_state.index[uri]
        return unless document

        @runtime_adapter.index_file(uri, document)
      rescue StandardError => e
        warn("[TypeGuessr] Error indexing #{uri}: #{e.message}")
      end

      def debug_enabled?
        %w[1 true].include?(ENV.fetch("TYPE_GUESSR_DEBUG", nil))
      end

      def start_debug_server
        @debug_server = DebugServer.new(@global_state)
        @debug_server.start
      rescue StandardError => e
        warn("[TypeGuessr] Failed to start debug server: #{e.message}")
      end
    end
  end
end
