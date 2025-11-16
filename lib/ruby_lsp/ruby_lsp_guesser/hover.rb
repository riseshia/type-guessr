# frozen_string_literal: true

require "prism"
require_relative "variable_type_resolver"
require_relative "hover_content_builder"

module RubyLsp
  module Guesser
    # Hover provider that coordinates type resolution and content generation
    # Delegates type resolution to VariableTypeResolver
    # Delegates content generation to HoverContentBuilder
    class Hover
      def initialize(response_builder, node_context, dispatcher, global_state = nil)
        @response_builder = response_builder
        @type_resolver = VariableTypeResolver.new(node_context, global_state)
        @content_builder = HoverContentBuilder.new(global_state)

        register_listeners(dispatcher)
      end

      def on_local_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_local_variable_write_node_enter(node)
        add_hover_content(node)
      end

      def on_local_variable_target_node_enter(node)
        add_hover_content(node)
      end

      def on_instance_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_class_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_global_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_self_node_enter(node)
        add_hover_content(node)
      end

      def on_required_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_optional_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_rest_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_required_keyword_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_optional_keyword_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_keyword_rest_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_block_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_forwarding_parameter_node_enter(node)
        add_hover_content(node)
      end

      private

      def register_listeners(dispatcher)
        dispatcher.register(
          self,
          :on_local_variable_read_node_enter,
          :on_local_variable_write_node_enter,
          :on_local_variable_target_node_enter,
          :on_instance_variable_read_node_enter,
          :on_class_variable_read_node_enter,
          :on_global_variable_read_node_enter,
          :on_self_node_enter,
          :on_required_parameter_node_enter,
          :on_optional_parameter_node_enter,
          :on_rest_parameter_node_enter,
          :on_required_keyword_parameter_node_enter,
          :on_optional_keyword_parameter_node_enter,
          :on_keyword_rest_parameter_node_enter,
          :on_block_parameter_node_enter,
          :on_forwarding_parameter_node_enter
        )
      end

      def add_hover_content(node)
        type_info = @type_resolver.resolve_type(node)
        return unless type_info

        # Try to infer type from method calls if available
        matching_types = @type_resolver.infer_type_from_methods(type_info[:method_calls])

        content = @content_builder.build(type_info, matching_types: matching_types)
        @response_builder.push(content, category: :documentation) if content
      end
    end
  end
end
