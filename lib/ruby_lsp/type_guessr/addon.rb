# frozen_string_literal: true

require "ruby_lsp/addon"
require_relative "config"
require_relative "constants"
require_relative "runtime_adapter"
require_relative "hover"
require_relative "debug_server"

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
        unless Config.enabled?
          message_queue << RubyLsp::Notification.window_log_message(
            "[TypeGuessr] Disabled via config",
            type: RubyLsp::Constant::MessageType::LOG
          )
          return
        end

        @global_state = global_state
        @message_queue = message_queue
        @runtime_adapter = RuntimeAdapter.new(global_state, message_queue)
        @debug_server = nil

        # Extend Ruby LSP's hover targets to include variables and parameters
        extend_hover_targets

        # Start background indexing (includes RBS preload)
        @runtime_adapter.start_indexing if Config.background_indexing?

        # Swap TypeInferrer for enhanced Go to Definition
        @runtime_adapter.swap_type_inferrer

        # Start debug server if enabled
        start_debug_server if Config.debug_server_enabled?

        debug_status = Config.debug? ? " (debug mode enabled)" : ""
        message_queue << RubyLsp::Notification.window_log_message(
          "[TypeGuessr] Activated#{debug_status}",
          type: RubyLsp::Constant::MessageType::LOG
        )
      end

      def deactivate
        @runtime_adapter&.restore_type_inferrer
        @debug_server&.stop
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        return unless @runtime_adapter

        Hover.new(@runtime_adapter, response_builder, node_context, dispatcher, @global_state)
      end

      # Handle file changes
      def workspace_did_change_watched_files(changes)
        return unless @runtime_adapter

        changes.each do |change|
          uri = URI(change[:uri])
          next unless uri.path&.end_with?(".rb")

          case change[:type]
          when RubyLsp::Constant::FileChangeType::CREATED,
               RubyLsp::Constant::FileChangeType::CHANGED
            reindex_file(uri)
          when RubyLsp::Constant::FileChangeType::DELETED
            file_path = uri.to_standardized_path
            @runtime_adapter.remove_indexed_file(file_path) if file_path
          end
        end
      end

      private def extend_hover_targets
        targets = RubyLsp::Listeners::Hover::ALLOWED_TARGETS

        Constants::HOVER_NODE_MAPPING.each_value do |target|
          targets << target unless targets.include?(target)
        end
      end

      private def reindex_file(uri)
        file_path = uri.path
        return unless file_path && File.exist?(file_path)

        source = File.read(file_path)
        @runtime_adapter.index_source(uri.to_s, source)
      rescue StandardError => e
        warn("[TypeGuessr] Error indexing #{uri}: #{e.message}")
      end

      private def start_debug_server
        port = Config.debug_server_port
        warn("[TypeGuessr] Starting debug server on port #{port}...")
        @debug_server = DebugServer.new(@global_state, @runtime_adapter, port: port)
        @debug_server.start
        warn("[TypeGuessr] Debug server started: http://127.0.0.1:#{port}")
      rescue StandardError => e
        warn("[TypeGuessr] Failed to start debug server: #{e.class}: #{e.message}")
        warn("[TypeGuessr] #{e.backtrace&.first(5)&.join("\n")}")
      end
    end
  end
end
