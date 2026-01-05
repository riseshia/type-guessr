# frozen_string_literal: true

require_relative "../../type_guessr/core/type_formatter"

module RubyLsp
  module TypeGuessr
    # Hover provider for TypeGuessr
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
        # Generate node_key from scope and Prism node
        # DefNode is indexed with parent scope (not including the method itself)
        exclude_method = node.is_a?(Prism::DefNode)
        scope_id = generate_scope_id(exclude_method: exclude_method)
        node_hash = generate_node_hash(node)
        return unless node_hash

        node_key = "#{scope_id}:#{node_hash}"

        # Find IR node by key (O(1) lookup)
        ir_node = @runtime_adapter.find_node_by_key(node_key)
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
        content += build_debug_info(result, ir_node) if debug_enabled?

        @response_builder.push(content, category: :documentation)
      rescue StandardError => e
        warn "[TypeGuessr] Error in add_hover_content: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end

      def add_def_node_hover(def_node)
        # Build method signature: (params) -> return_type
        params_str = format_params(def_node.params)
        return_result = @runtime_adapter.infer_type(def_node)
        return_type_str = TypeFormatter.format(return_result.type)

        signature = "(#{params_str}) -> #{return_type_str}"
        content = "**Method Signature:** `#{signature}`"

        content += build_debug_info(return_result) if debug_enabled?

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

              if debug_enabled?
                content += "\n\n**[TypeGuessr Debug]**"
                content += "\n\n**Receiver:** `#{TypeFormatter.format(receiver_type)}`"
                if sig_strs.size > 1
                  content += "\n\n**Overloads:**\n"
                  sig_strs.each { |s| content += "- `#{s}`\n" }
                end
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
        content += build_debug_info(result) if debug_enabled?
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

      def build_debug_info(result, ir_node = nil)
        info = "\n\n**[TypeGuessr Debug]**"
        info += "\n\n**Reason:** #{result.reason}"
        info += "\n\n**Source:** #{result.source}"
        if ir_node
          called_methods = extract_called_methods(ir_node)
          info += "\n\n**Method calls:** #{called_methods.join(", ")}" if called_methods.any?
        end
        info
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

      # Generate scope_id from node_context
      # Format: "ClassName#method_name" or "ClassName" or "#method_name" or ""
      # @param exclude_method [Boolean] Whether to exclude method from scope (for DefNode)
      def generate_scope_id(exclude_method: false)
        class_path = @node_context.nesting.map do |n|
          n.is_a?(String) ? n : n.name.to_s
        end.join("::")

        method_name = exclude_method ? nil : @node_context.surrounding_method

        if method_name
          "#{class_path}##{method_name}"
        else
          class_path
        end
      end

      # Generate node_hash from Prism node to match IR node_hash format
      def generate_node_hash(node)
        line = node.location.start_line
        case node
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode,
             Prism::InstanceVariableReadNode, Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode,
             Prism::ClassVariableReadNode, Prism::ClassVariableWriteNode, Prism::ClassVariableTargetNode,
             Prism::GlobalVariableReadNode, Prism::GlobalVariableWriteNode, Prism::GlobalVariableTargetNode
          "var:#{node.name}:#{line}"
        when Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
             Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
             Prism::KeywordRestParameterNode, Prism::BlockParameterNode
          # Check if this is a block parameter (parent is BlockParametersNode)
          if block_parameter?(node)
            index = block_parameter_index(node)
            "bparam:#{index}:#{line}"
          else
            "param:#{node.name}:#{line}"
          end
        when Prism::ForwardingParameterNode
          "param:...:#{line}"
        when Prism::CallNode
          # Use message_loc for accurate line number
          call_line = node.message_loc&.start_line || line
          "call:#{node.name}:#{call_line}"
        when Prism::DefNode
          # Use name_loc for accurate line number
          def_line = node.name_loc&.start_line || line
          "def:#{node.name}:#{def_line}"
        when Prism::SelfNode
          class_path = @node_context.nesting.map do |n|
            n.is_a?(String) ? n : n.name.to_s
          end.join("::")
          "self:#{class_path}:#{line}"
        end
      end

      # Check if a parameter node is inside a block (not a method definition)
      def block_parameter?(node)
        call_node = @node_context.call_node
        return false unless call_node&.block

        # Check if this parameter is in the block's parameters
        block_params = call_node.block.parameters&.parameters
        return false unless block_params

        all_params = collect_block_params(block_params)
        all_params.include?(node)
      end

      # Get the index of a block parameter
      def block_parameter_index(node)
        call_node = @node_context.call_node
        return 0 unless call_node&.block

        block_params = call_node.block.parameters&.parameters
        return 0 unless block_params

        all_params = collect_block_params(block_params)
        all_params.index(node) || 0
      end

      # Collect all positional parameters from a ParametersNode
      def collect_block_params(params_node)
        all_params = []
        all_params.concat(params_node.requireds || [])
        all_params.concat(params_node.optionals || [])
        all_params << params_node.rest if params_node.rest
        all_params.concat(params_node.posts || [])
        all_params
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
