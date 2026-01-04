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
        required_parameter
        optional_parameter
        rest_parameter
        required_keyword_parameter
        optional_keyword_parameter
        keyword_rest_parameter
        block_parameter
        forwarding_parameter
        call
        def
        self
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

      # Core IR module shortcut
      IR = ::TypeGuessr::Core::IR
      private_constant :IR

      def add_hover_content(node)
        # Extract position from Prism node
        # Use more specific location when available:
        # - For DefNode: use name_loc to match the method name position
        # - For CallNode: use message_loc to match the method name position
        location = if node.respond_to?(:name_loc) && node.name_loc
                     node.name_loc
                   elsif node.respond_to?(:message_loc) && node.message_loc
                     node.message_loc
                   else
                     node.location
                   end
        line = location.start_line - 1 # Convert to 0-indexed
        column = location.start_column

        # Find IR node at position (searches all files since we don't have URI)
        ir_node = @runtime_adapter.find_node_at(nil, line, column)
        return unless ir_node

        # Handle DefNode specially - show method signature
        if ir_node.is_a?(IR::DefNode)
          add_def_node_hover(ir_node)
          return
        end

        # Handle CallNode specially - show RBS method signature
        if ir_node.is_a?(IR::CallNode)
          add_call_node_hover(ir_node)
          return
        end

        # Infer type
        result = @runtime_adapter.infer_type(ir_node)

        # Format type with definition link if available
        formatted_type = format_type_with_link(result.type)

        # Build hover content
        content = "**Guessed Type:** #{formatted_type}"

        # Add debug info if enabled
        if debug_enabled?
          content += "\n\n**[TypeGuessr Debug]**"
          content += "\n\n**Reason:** #{result.reason}"
          content += "\n\n**Source:** #{result.source}"

          # Add method calls info for variables/params with duck typing
          called_methods = extract_called_methods(ir_node)
          content += "\n\n**Method calls:** #{called_methods.join(", ")}" if called_methods.any?
        end

        @response_builder.push(content, category: :documentation)
      end

      def add_def_node_hover(def_node)
        # Build method signature: (params) -> return_type
        params_str = format_params(def_node.params)
        return_result = @runtime_adapter.infer_type(def_node)
        return_type_str = TypeFormatter.format(return_result.type)

        signature = "(#{params_str}) -> #{return_type_str}"
        content = "**Method Signature:** `#{signature}`"

        content += "\n\n**Reason:** #{return_result.reason}" if debug_enabled?

        @response_builder.push(content, category: :documentation)
      end

      def add_call_node_hover(call_node)
        # Get receiver type to look up RBS signature
        if call_node.receiver
          receiver_result = @runtime_adapter.infer_type(call_node.receiver)
          receiver_type = receiver_result.type

          # Get the class name for RBS lookup
          class_name = extract_class_name(receiver_type)

          if class_name
            # Look up RBS signature
            rbs_provider = ::TypeGuessr::Core::RBSProvider.instance
            signatures = rbs_provider.get_method_signatures(class_name, call_node.method.to_s)

            if signatures.any?
              # Format the signature(s)
              sig_strs = signatures.map { |sig| sig.method_type.to_s }
              content = "**Method Signature:** `#{sig_strs.first}`"

              if sig_strs.size > 1 && debug_enabled?
                content += "\n\n**Overloads:**\n"
                sig_strs.each { |s| content += "- `#{s}`\n" }
              end

              @response_builder.push(content, category: :documentation)
              return
            end
          end
        end

        # Fallback: show inferred return type
        result = @runtime_adapter.infer_type(call_node)
        type_str = TypeFormatter.format(result.type)

        # For project methods, show as signature format
        content = if result.source == :project
                    "**Guessed Signature:** `() -> #{type_str}`"
                  else
                    "**Guessed Type:** `#{type_str}`"
                  end
        @response_builder.push(content, category: :documentation)
      end

      def extract_class_name(type)
        case type
        when Types::ClassInstance
          type.name
        when Types::ArrayType
          "Array"
        when Types::HashType, Types::HashShape
          "Hash"
        end
      end

      def format_params(params)
        return "" if params.nil? || params.empty?

        params.map do |param|
          param_type = infer_param_type(param)
          type_str = TypeFormatter.format(param_type)

          case param.kind
          when :required
            "#{type_str} #{param.name}"
          when :optional
            "?#{type_str} #{param.name}"
          when :rest
            "*#{type_str} #{param.name}"
          when :keyword_required
            "#{param.name}: #{type_str}"
          when :keyword_optional
            "#{param.name}: ?#{type_str}"
          when :keyword_rest
            "**#{type_str} #{param.name}"
          when :block
            "&#{type_str} #{param.name}"
          when :forwarding
            "..."
          else
            "#{type_str} #{param.name}"
          end
        end.join(", ")
      end

      def infer_param_type(param)
        result = @runtime_adapter.infer_type(param)
        result.type
      end

      def debug_enabled?
        %w[1 true].include?(ENV.fetch("TYPE_GUESSR_DEBUG", nil))
      end

      def extract_called_methods(ir_node)
        case ir_node
        when IR::VariableNode, IR::ParamNode
          ir_node.called_methods || []
        when IR::BlockParamSlot
          # For block params, check the underlying param node
          []
        else
          []
        end
      end

      # Format type with definition link if available
      def format_type_with_link(type)
        formatted = TypeFormatter.format(type)

        # Only link ClassInstance types
        return "`#{formatted}`" unless type.is_a?(Types::ClassInstance)

        # Try to find the class definition in the index
        entry = find_type_entry(type.name)
        return "`#{formatted}`" unless entry

        location_link = build_location_link(entry)
        return "`#{formatted}`" unless location_link

        "[`#{formatted}`](#{location_link})"
      end

      # Find entry for a type name in RubyIndexer
      def find_type_entry(type_name)
        return nil unless @global_state&.index

        entries = @global_state.index.resolve(type_name, [])
        return nil if entries.nil? || entries.empty?

        # Return the first class/module entry
        entries.find { |e| e.is_a?(RubyIndexer::Entry::Namespace) }
      end

      # Build a location link from an entry
      def build_location_link(entry)
        uri = entry.uri
        return nil if uri.nil?

        location = entry.respond_to?(:name_location) ? entry.name_location : entry.location
        return nil if location.nil?

        "#{uri}#L#{location.start_line},#{location.start_column + 1}-" \
          "#{location.end_line},#{location.end_column + 1}"
      end
    end
  end
end
