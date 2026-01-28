# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Hover provider for TypeGuessr
    class Hover
      # Core layer shortcuts
      Types = ::TypeGuessr::Core::Types
      private_constant :Types

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
        method_sig = @runtime_adapter.build_method_signature(def_node)
        content = "**Guessed Signature:** `#{method_sig}`"

        if debug_enabled?
          return_result = @runtime_adapter.infer_type(def_node)
          content += build_debug_info(return_result)
        end

        @response_builder.push(content, category: :documentation)
      end

      def add_call_node_hover(call_node)
        # Special case: Handle .new calls to show constructor signature
        # Support both ClassName.new (ConstantNode) and self.new (SelfNode) in singleton methods
        if call_node.method == :new &&
           (call_node.receiver.is_a?(IR::ConstantNode) || call_node.receiver.is_a?(IR::SelfNode))
          add_new_call_hover(call_node)
          return
        end

        # Handle implicit self calls (receiver is nil)
        unless call_node.receiver
          def_node = lookup_def_node_for_implicit_self(call_node)
          if def_node
            add_def_node_hover(def_node)
            return
          end
        end

        # Get receiver type to look up method signature
        if call_node.receiver
          # For ConstantNode receiver (e.g., File.exist?, RBS::Environment.from_loader),
          # directly create SingletonType without relying on constant_kind_provider
          receiver_type = if call_node.receiver.is_a?(IR::ConstantNode)
                            Types::SingletonType.new(call_node.receiver.name)
                          else
                            @runtime_adapter.infer_type(call_node.receiver).type
                          end

          # Get the class name for signature lookup
          class_name = extract_class_name(receiver_type)

          if class_name
            # Try to find DefNode first (for project methods)
            # Use the same inference logic as DefNode hover
            unless receiver_type.is_a?(Types::SingletonType)
              def_node = @runtime_adapter.lookup_method(class_name, call_node.method.to_s)
              if def_node
                add_def_node_hover(def_node)
                return
              end
            end

            # Fall back to RBS signature lookup (for stdlib/gems)
            # Use class method lookup for SingletonType (e.g., RBS::Environment.from_loader)
            signatures = if receiver_type.is_a?(Types::SingletonType)
                           @runtime_adapter.signature_provider.get_class_method_signatures(
                             class_name, call_node.method.to_s
                           )
                         else
                           @runtime_adapter.signature_provider.get_method_signatures(
                             class_name, call_node.method.to_s
                           )
                         end

            if signatures.any?
              # Format the signature(s)
              sig_strs = signatures.map { |sig| sig.method_type.to_s }
              content = "**Guessed Signature:** `#{sig_strs.first}`"

              if debug_enabled?
                content += "\n\n**[TypeGuessr Debug]**"
                content += "\n\n**Receiver:** `#{receiver_type}`"
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

        # Fallback: show inferred return type as signature format
        # All method calls should show signature format (not just project methods)
        result = @runtime_adapter.infer_type(call_node)
        type_str = result.type.to_s

        # Build signature with parameter info from RubyIndexer
        params_str = build_call_signature_params(call_node)
        content = "**Guessed Signature:** `(#{params_str}) -> #{type_str}`"
        content += build_debug_info(result) if debug_enabled?
        @response_builder.push(content, category: :documentation)
      end

      # Build parameter signature for a method call using RubyIndexer
      def build_call_signature_params(call_node)
        method_entry = lookup_method_entry_for_call(call_node)

        if method_entry&.signatures&.any?
          format_params_from_entry(method_entry, call_node.args)
        elsif call_node.args&.any?
          format_params_from_args(call_node.args)
        else
          ""
        end
      end

      # Look up method entry from RubyIndexer based on call node
      def lookup_method_entry_for_call(call_node)
        return nil unless @global_state&.index
        return nil unless call_node.receiver

        receiver_result = @runtime_adapter.infer_type(call_node.receiver)

        case receiver_result.type
        when Types::SingletonType
          lookup_class_method_entry(receiver_result.type.name, call_node.method.to_s)
        when Types::ClassInstance
          lookup_instance_method_entry(receiver_result.type.name, call_node.method.to_s)
        end
      end

      # Format parameters from RubyIndexer method entry with inferred argument types
      def format_params_from_entry(method_entry, args)
        params = method_entry.signatures.first.parameters
        return "" if params.nil? || params.empty?

        params.each_with_index.map do |param, i|
          arg_type = if args && i < args.size
                       @runtime_adapter.infer_type(args[i]).type.to_s
                     else
                       "untyped"
                     end
          format_single_param(param, arg_type)
        end.join(", ")
      end

      # Format a single parameter based on its type
      def format_single_param(param, arg_type)
        param_name = param.name.to_s

        case param
        when RubyIndexer::Entry::RequiredParameter
          "#{arg_type} #{param_name}"
        when RubyIndexer::Entry::OptionalParameter
          "?#{arg_type} #{param_name}"
        when RubyIndexer::Entry::RestParameter
          "*#{arg_type} #{param_name}"
        when RubyIndexer::Entry::KeywordParameter
          "#{param_name}: #{arg_type}"
        when RubyIndexer::Entry::OptionalKeywordParameter
          "?#{param_name}: #{arg_type}"
        when RubyIndexer::Entry::KeywordRestParameter
          "**#{arg_type} #{param_name}"
        when RubyIndexer::Entry::BlockParameter
          "&#{param_name}"
        else
          "#{arg_type} #{param_name}"
        end
      end

      # Format arguments when no method entry is available
      def format_params_from_args(args)
        args.each_with_index.map do |arg, i|
          arg_type = @runtime_adapter.infer_type(arg).type.to_s
          "#{arg_type} arg#{i + 1}"
        end.join(", ")
      end

      # Look up class method entry from RubyIndexer
      def lookup_class_method_entry(class_name, method_name)
        return nil unless @global_state&.index

        # Query singleton class for the method
        # Ruby LSP uses unqualified name for singleton class (e.g., "RBS::Environment::<Class:Environment>")
        unqualified_name = ::TypeGuessr::Core::IR.extract_last_name(class_name)
        singleton_name = "#{class_name}::<Class:#{unqualified_name}>"
        entries = @global_state.index.resolve_method(method_name, singleton_name)
        return nil if entries.nil? || entries.empty?

        entries.first
      rescue RubyIndexer::Index::NonExistingNamespaceError
        nil
      end

      # Look up instance method entry from RubyIndexer
      def lookup_instance_method_entry(class_name, method_name)
        return nil unless @global_state&.index

        entries = @global_state.index.resolve_method(method_name, class_name)
        return nil if entries.nil? || entries.empty?

        entries.first
      rescue RubyIndexer::Index::NonExistingNamespaceError
        nil
      end

      # Look up DefNode for implicit self calls (receiver is nil)
      # Searches in current class scope and falls back to top-level
      def lookup_def_node_for_implicit_self(call_node)
        method_name = call_node.method.to_s

        # Get current class scope from node_context
        class_name = @node_context.nesting.map { |n| n.is_a?(String) ? n : n.name.to_s }.join("::")

        # Try current class scope first
        def_node = @runtime_adapter.lookup_method(class_name, method_name) if class_name && !class_name.empty?
        return def_node if def_node

        # Fall back to top-level (empty class name)
        @runtime_adapter.lookup_method("", method_name)
      end

      def extract_class_name(type)
        case type
        when Types::ClassInstance
          type.name
        when Types::SingletonType
          type.name
        when Types::ArrayType
          "Array"
        when Types::HashType, Types::HashShape
          "Hash"
        end
      end

      # Handle .new calls to show constructor signature
      def add_new_call_hover(call_node)
        class_name = resolve_receiver_class_name(call_node.receiver)
        result = @runtime_adapter.build_constructor_signature(class_name)

        content = case result[:source]
                  when :project, :default
                    "**Guessed Signature:** `#{result[:signature]}`"
                  when :rbs
                    sig_str = result[:rbs_signature].method_type.to_s
                    sig_str = sig_str.sub(/-> .+$/, "-> #{class_name}")
                    "**Guessed Signature:** `#{sig_str}`"
                  end

        content += build_debug_info_for_new(result[:source], class_name) if debug_enabled?

        @response_builder.push(content, category: :documentation)
      end

      # Resolve receiver to class name (handles aliases via type inference)
      def resolve_receiver_class_name(receiver)
        receiver_result = @runtime_adapter.infer_type(receiver)
        case receiver_result.type
        when Types::SingletonType then receiver_result.type.name
        else receiver.name
        end
      end

      # Build debug info for .new calls
      def build_debug_info_for_new(source, class_name)
        info = "\n\n**[TypeGuessr Debug]**"
        info += "\n\n**Class:** `#{class_name}`"
        info += "\n\n**Source:** #{source}"
        info
      end

      def debug_enabled?
        Config.debug?
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
        when IR::LocalWriteNode, IR::LocalReadNode,
             IR::InstanceVariableWriteNode, IR::InstanceVariableReadNode,
             IR::ClassVariableWriteNode, IR::ClassVariableReadNode,
             IR::ParamNode
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
        when Prism::LocalVariableWriteNode, Prism::LocalVariableTargetNode
          "local_write:#{node.name}:#{line}"
        when Prism::LocalVariableReadNode
          "local_read:#{node.name}:#{line}"
        when Prism::InstanceVariableWriteNode, Prism::InstanceVariableTargetNode
          "ivar_write:#{node.name}:#{line}"
        when Prism::InstanceVariableReadNode
          "ivar_read:#{node.name}:#{line}"
        when Prism::ClassVariableWriteNode, Prism::ClassVariableTargetNode
          "cvar_write:#{node.name}:#{line}"
        when Prism::ClassVariableReadNode
          "cvar_read:#{node.name}:#{line}"
        when Prism::GlobalVariableWriteNode, Prism::GlobalVariableTargetNode
          "global_write:#{node.name}:#{line}"
        when Prism::GlobalVariableReadNode
          "global_read:#{node.name}:#{line}"
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
        formatted = type.to_s

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
