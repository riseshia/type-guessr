# frozen_string_literal: true

require "ruby_lsp/addon"
require_relative "../../type_guessr/core/type_formatter"

module RubyLsp
  module TypeGuessr
    # Hover provider for TypeGuessr
    # Provides type information on hover using IR-based inference
    class Hover
      def initialize(runtime_adapter, response_builder, node_context, dispatcher)
        @runtime_adapter = runtime_adapter
        @response_builder = response_builder
        @node_context = node_context
        @dispatcher = dispatcher

        # Register for all hover events
        dispatcher.register(self, :on_hover)
      end

      def on_hover(node, _event)
        # Get position from node
        location = node.location
        uri = @node_context.uri
        line = location.start_line - 1 # Convert to 0-indexed
        column = location.start_column

        # Find IR node at position
        ir_node = @runtime_adapter.find_node_at(uri, line, column)
        return unless ir_node

        # Infer type
        result = @runtime_adapter.infer_type(ir_node)
        return if result.type.is_a?(::TypeGuessr::Core::Types::Unknown)

        # Format type
        type_str = ::TypeGuessr::Core::TypeFormatter.format(result.type)

        # Build hover content
        content = "**Guessed Type:** `#{type_str}`"

        # Add debug info if enabled
        if debug_enabled?
          content += "\n\n**Reason:** #{result.reason}"
          content += "\n\n**Source:** #{result.source}"
        end

        @response_builder.push(content, category: :information)
      end

      private

      def debug_enabled?
        %w[1 true].include?(ENV.fetch("TYPE_GUESSR_DEBUG", nil))
      end
    end
  end
end
