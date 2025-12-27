# frozen_string_literal: true

require "prism"
require_relative "variable_type_resolver"
require_relative "hover_content_builder"
require_relative "../../type_guessr/core/rbs_provider"

module RubyLsp
  module TypeGuessr
    # No-op hover listener used when TypeGuessr is disabled.
    # It intentionally registers no listeners.
    class NoopHover
      def initialize(*); end
    end

    # Hover provider that coordinates type resolution and content generation
    # Delegates type resolution to VariableTypeResolver
    # Delegates content generation to HoverContentBuilder
    class Hover
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
        self
        required_parameter
        optional_parameter
        rest_parameter
        required_keyword_parameter
        optional_keyword_parameter
        keyword_rest_parameter
        block_parameter
        forwarding_parameter
        call
      ].freeze

      def initialize(response_builder, node_context, dispatcher, global_state = nil)
        @response_builder = response_builder
        @type_resolver = VariableTypeResolver.new(node_context, global_state)
        @content_builder = HoverContentBuilder.new(global_state)

        register_listeners(dispatcher)
      end

      # Dynamically define listener methods for each node type
      HOVER_NODE_TYPES.each do |node_type|
        define_method(:"on_#{node_type}_node_enter") do |node|
          add_hover_content(node)
        end
      end

      # Override on_call_node_enter for method call hover
      def on_call_node_enter(node)
        return unless node.receiver

        # Phase 5.2a: Only handle variable receivers
        return unless variable_receiver?(node.receiver)

        # 1. Infer receiver type using existing VariableTypeResolver
        receiver_type = resolve_receiver_type(node.receiver)
        return if receiver_type.nil? || receiver_type == ::TypeGuessr::Core::Types::Unknown.instance

        # 2. Query RBS signatures
        rbs_provider = ::TypeGuessr::Core::RBSProvider.new
        signatures = rbs_provider.get_method_signatures(
          extract_type_name(receiver_type),
          node.name.to_s
        )
        return if signatures.empty?

        # 3. Format and output
        content = format_method_signatures(node.name, signatures)
        @response_builder.push(content, category: :documentation)
      end

      private

      def register_listeners(dispatcher)
        # Dynamically generate listener method names from HOVER_NODE_TYPES
        listener_methods = HOVER_NODE_TYPES.map { |node_type| :"on_#{node_type}_node_enter" }
        dispatcher.register(self, *listener_methods)
      end

      def add_hover_content(node)
        type_info = @type_resolver.resolve_type(node)
        return if !type_info

        # Try to infer type from method calls if available
        matching_types = @type_resolver.infer_type_from_methods(type_info[:method_calls])

        # Collect all type names that need entries (both direct_type and matching_types)
        all_type_names = matching_types.dup
        all_type_names << type_info[:direct_type] if type_info[:direct_type]

        # Get entries for linking to type definitions
        type_entries = @type_resolver.get_type_entries(all_type_names)

        content = @content_builder.build(type_info, matching_types: matching_types, type_entries: type_entries)
        @response_builder.push(content, category: :documentation) if content
      end

      # Check if node is a variable receiver (local, instance, or class variable)
      # @param node [Prism::Node] the node to check
      # @return [Boolean] true if node is a variable receiver
      def variable_receiver?(node)
        node.is_a?(Prism::LocalVariableReadNode) ||
          node.is_a?(Prism::InstanceVariableReadNode) ||
          node.is_a?(Prism::ClassVariableReadNode)
      end

      # Resolve the type of a receiver node
      # @param receiver [Prism::Node] the receiver node
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve_receiver_type(receiver)
        type_info = @type_resolver.resolve_type(receiver)
        return nil unless type_info

        # Return direct type if available
        type_info[:direct_type]
      end

      # Extract type name from a Types object
      # @param type_obj [TypeGuessr::Core::Types::Type] the type object
      # @return [String] the type name
      def extract_type_name(type_obj)
        case type_obj
        when ::TypeGuessr::Core::Types::ClassInstance
          type_obj.name
        else
          ::TypeGuessr::Core::TypeFormatter.format(type_obj)
        end
      end

      # Format method signatures for display
      # @param method_name [Symbol] the method name
      # @param signatures [Array<TypeGuessr::Core::RBSProvider::Signature>] the signatures
      # @return [String] formatted signature content
      def format_method_signatures(method_name, signatures)
        sig_strings = signatures.map do |sig|
          sig.method_type.to_s
        end

        "**Method:** `#{method_name}`\n\n**Signatures:**\n```ruby\n#{sig_strings.join("\n")}\n```"
      end
    end
  end
end
