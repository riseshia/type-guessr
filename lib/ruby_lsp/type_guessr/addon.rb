# frozen_string_literal: true

require "ruby_lsp/addon"
require "prism"
require_relative "hover"
require_relative "runtime_adapter"
require_relative "../../type_guessr/version" unless defined?(TypeGuessr::VERSION)

module RubyLsp
  module TypeGuessr
    # Ruby LSP addon for TypeGuessr
    # Provides hover tooltip functionality for Ruby code
    class Addon < ::RubyLsp::Addon
      # Node types to add to Ruby LSP's ALLOWED_TARGETS for hover support
      HOVER_TARGET_NODES = [
        Prism::LocalVariableReadNode,
        Prism::LocalVariableWriteNode,
        Prism::LocalVariableTargetNode,
        Prism::RequiredParameterNode,
        Prism::OptionalParameterNode,
        Prism::RestParameterNode,
        Prism::RequiredKeywordParameterNode,
        Prism::OptionalKeywordParameterNode,
        Prism::KeywordRestParameterNode,
        Prism::BlockParameterNode,
        Prism::ForwardingParameterNode,
        Prism::SelfNode
      ].freeze

      def initialize
        super
        @runtime_adapter = nil
      end

      def name
        "TypeGuessr"
      end

      def version
        ::TypeGuessr::VERSION
      end

      def activate(global_state, message_queue)
        @global_state = global_state
        @runtime_adapter = RuntimeAdapter.new(global_state, message_queue)

        log_message(message_queue, "Activating TypeGuessr LSP addon #{::TypeGuessr::VERSION}.")

        @runtime_adapter.swap_type_inferrer
        extend_hover_targets
        @runtime_adapter.start_ast_traversal
      end

      def deactivate
        @runtime_adapter&.restore_type_inferrer
        @runtime_adapter = nil
      end

      # Handle file change notifications from LSP client
      # Re-index files when they are created, updated, or deleted
      def workspace_did_change_watched_files(changes)
        changes.each do |change|
          uri = URI(change[:uri])
          file_path = uri.to_standardized_path
          next if file_path.nil? || File.directory?(file_path)
          next unless file_path.end_with?(".rb")

          case change[:type]
          when Constant::FileChangeType::CREATED, Constant::FileChangeType::CHANGED
            @runtime_adapter&.reindex_file(file_path)
          when Constant::FileChangeType::DELETED
            @runtime_adapter&.clear_file_index(file_path)
          end
        end
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        Hover.new(response_builder, node_context, dispatcher, @global_state)
      end

      private

      # Extend Ruby LSP's ALLOWED_TARGETS to support local variables, parameters, and self for hover
      def extend_hover_targets
        targets = RubyLsp::Listeners::Hover::ALLOWED_TARGETS

        HOVER_TARGET_NODES.each do |target|
          targets << target unless targets.include?(target)
        end
      end

      def log_message(message_queue, message)
        return unless message_queue
        return if message_queue.closed?

        message_queue << RubyLsp::Notification.window_log_message(
          "[TypeGuessr] #{message}",
          type: RubyLsp::Constant::MessageType::LOG
        )
      end
    end
  end
end
