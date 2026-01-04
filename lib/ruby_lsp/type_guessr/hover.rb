# frozen_string_literal: true

require_relative "../../type_guessr/core/type_formatter"

module RubyLsp
  module TypeGuessr
    # Hover provider for TypeGuessr
    # Provides type information on hover using IR-based inference
    class Hover
      # Core layer shortcuts
      TypeFormatter = ::TypeGuessr::Core::TypeFormatter
      Types = ::TypeGuessr::Core::Types
      private_constant :TypeFormatter, :Types

      # Define all node types that should trigger hover content
      HOVER_NODE_TYPES = %i[
        local_variable_read
        local_variable_write
        local_variable_target
        instance_variable_read
        instance_variable_write
        instance_variable_target
        class_variable_read
        class_variable_write
        class_variable_target
        global_variable_read
        global_variable_write
        global_variable_target
        call
      ].freeze

      def initialize(runtime_adapter, response_builder, node_context, dispatcher, global_state)
        @runtime_adapter = runtime_adapter
        @response_builder = response_builder
        @node_context = node_context
        @global_state = global_state

        register_listeners(dispatcher)
      end

      # Dynamically define handler methods for each node type
      HOVER_NODE_TYPES.each do |node_type|
        define_method(:"on_#{node_type}_node_enter") do |node|
          add_hover_content(node)
        end
      end

      private

      def register_listeners(dispatcher)
        dispatcher.register(
          self,
          *HOVER_NODE_TYPES.map { |type| :"on_#{type}_node_enter" }
        )
      end

      def add_hover_content(node)
        # Extract position from Prism node
        location = node.location
        line = location.start_line - 1 # Convert to 0-indexed
        column = location.start_column

        # Find IR node at position (searches all files since we don't have URI)
        ir_node = @runtime_adapter.find_node_at(nil, line, column)
        return unless ir_node

        # Infer type
        result = @runtime_adapter.infer_type(ir_node)
        return if result.type.is_a?(Types::Unknown)

        # Format type
        type_str = TypeFormatter.format(result.type)

        # Build hover content
        content = "**Guessed Type:** `#{type_str}`"

        # Add debug info if enabled
        if debug_enabled?
          content += "\n\n**Reason:** #{result.reason}"
          content += "\n\n**Source:** #{result.source}"
        end

        @response_builder.push(content, category: :documentation)
      end

      def debug_enabled?
        %w[1 true].include?(ENV.fetch("TYPE_GUESSR_DEBUG", nil))
      end
    end
  end
end
