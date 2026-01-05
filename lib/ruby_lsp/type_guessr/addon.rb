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
      # Node types to add to Ruby LSP's ALLOWED_TARGETS for hover support
      HOVER_TARGET_NODES = [
        Prism::LocalVariableReadNode,
        Prism::LocalVariableWriteNode,
        Prism::LocalVariableTargetNode,
        Prism::InstanceVariableReadNode,
        Prism::InstanceVariableWriteNode,
        Prism::InstanceVariableTargetNode,
        Prism::ClassVariableReadNode,
        Prism::ClassVariableWriteNode,
        Prism::ClassVariableTargetNode,
        Prism::GlobalVariableReadNode,
        Prism::GlobalVariableWriteNode,
        Prism::GlobalVariableTargetNode,
        Prism::SelfNode,
        Prism::RequiredParameterNode,
        Prism::OptionalParameterNode,
        Prism::RestParameterNode,
        Prism::RequiredKeywordParameterNode,
        Prism::OptionalKeywordParameterNode,
        Prism::KeywordRestParameterNode,
        Prism::BlockParameterNode,
        Prism::ForwardingParameterNode,
        Prism::CallNode,
        Prism::DefNode,
      ].freeze

      attr_reader :runtime_adapter

      def name
        "TypeGuessr"
      end

      def activate(global_state, message_queue)
        @global_state = global_state
        @message_queue = message_queue
        @runtime_adapter = RuntimeAdapter.new(global_state, message_queue)
        @debug_server = nil

        # Extend Ruby LSP's hover targets to include variables and parameters
        extend_hover_targets

        # Preload RBS environment
        ::TypeGuessr::Core::RBSProvider.instance.preload

        # Start background indexing
        @runtime_adapter.start_indexing

        # Start debug server if enabled
        start_debug_server if debug_enabled?

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
        return unless Config.enabled?

        Hover.new(@runtime_adapter, response_builder, node_context, dispatcher, @global_state)
      end

      # Handle file changes
      def workspace_did_change_watched_files(changes)
        return unless Config.enabled?

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

      def extend_hover_targets
        targets = RubyLsp::Listeners::Hover::ALLOWED_TARGETS

        HOVER_TARGET_NODES.each do |target|
          targets << target unless targets.include?(target)
        end
      end

      def reindex_file(uri)
        file_path = uri.path
        return unless file_path && File.exist?(file_path)

        source = File.read(file_path)
        @runtime_adapter.index_source(uri.to_s, source)
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
