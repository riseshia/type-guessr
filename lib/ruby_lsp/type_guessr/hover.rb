# frozen_string_literal: true

require "prism"
require_relative "variable_type_resolver"
require_relative "hover_content_builder"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "../../type_guessr/core/flow_analyzer"

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
        def
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

      # Override on_def_node_enter for method definition hover
      def on_def_node_enter(node)
        # 1. Infer parameter types from default values
        param_types = infer_parameter_types(node.parameters)

        # 2. Infer return type using FlowAnalyzer
        return_type = infer_return_type(node)

        # 3. Format and display signature
        signature = format_def_signature(node.parameters, param_types, return_type)
        @response_builder.push(signature, category: :documentation)
      rescue StandardError => e
        # Gracefully handle errors - don't show anything on failure
        warn "DefNodeHover error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        warn e.backtrace.join("\n") if ENV["DEBUG"]
        nil
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

      # Infer parameter types from default values
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @return [Array<TypeGuessr::Core::Types::Type>] array of parameter types
      def infer_parameter_types(parameters)
        return [] if parameters.nil?

        all_params = []
        all_params.concat(parameters.requireds) if parameters.requireds
        all_params.concat(parameters.optionals) if parameters.optionals
        all_params.concat(parameters.keywords) if parameters.keywords
        all_params << parameters.rest if parameters.rest
        all_params << parameters.keyword_rest if parameters.keyword_rest
        all_params << parameters.block if parameters.block

        all_params.compact.map do |param|
          infer_single_parameter_type(param)
        end
      end

      # Infer type for a single parameter
      # @param param [Prism::Node] the parameter node
      # @return [TypeGuessr::Core::Types::Type] the inferred type
      def infer_single_parameter_type(param)
        case param
        when Prism::OptionalParameterNode, Prism::OptionalKeywordParameterNode
          # Infer from default value
          if param.value
            analyze_value_type_for_param(param.value) || ::TypeGuessr::Core::Types::Unknown.instance
          else
            ::TypeGuessr::Core::Types::Unknown.instance
          end
        else
          # Required params, rest, block → untyped
          ::TypeGuessr::Core::Types::Unknown.instance
        end
      end

      # Analyze value type for parameter (reuse existing logic)
      # @param node [Prism::Node] the value node
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type
      def analyze_value_type_for_param(node)
        case node
        when Prism::IntegerNode
          ::TypeGuessr::Core::Types::ClassInstance.new("Integer")
        when Prism::FloatNode
          ::TypeGuessr::Core::Types::ClassInstance.new("Float")
        when Prism::StringNode, Prism::InterpolatedStringNode
          ::TypeGuessr::Core::Types::ClassInstance.new("String")
        when Prism::SymbolNode
          ::TypeGuessr::Core::Types::ClassInstance.new("Symbol")
        when Prism::TrueNode
          ::TypeGuessr::Core::Types::ClassInstance.new("TrueClass")
        when Prism::FalseNode
          ::TypeGuessr::Core::Types::ClassInstance.new("FalseClass")
        when Prism::NilNode
          ::TypeGuessr::Core::Types::ClassInstance.new("NilClass")
        when Prism::ArrayNode
          ::TypeGuessr::Core::Types::ClassInstance.new("Array")
        when Prism::HashNode
          ::TypeGuessr::Core::Types::ClassInstance.new("Hash")
        when Prism::CallNode
          # Only handle .new calls
          if node.name == :new && node.receiver
            class_name = extract_class_name_from_new_call(node.receiver)
            ::TypeGuessr::Core::Types::ClassInstance.new(class_name) if class_name
          end
        end
      end

      # Extract class name from .new call receiver
      # @param receiver [Prism::Node] the receiver node
      # @return [String, nil] the class name or nil
      def extract_class_name_from_new_call(receiver)
        case receiver
        when Prism::ConstantReadNode
          receiver.name.to_s
        when Prism::ConstantPathNode
          receiver.slice
        end
      end

      # Infer return type using FlowAnalyzer
      # @param node [Prism::DefNode] the method definition node
      # @return [TypeGuessr::Core::Types::Type] the inferred return type
      def infer_return_type(node)
        source = node.slice
        analyzer = ::TypeGuessr::Core::FlowAnalyzer.new
        result = analyzer.analyze(source)
        result.return_type_for_method(node.name.to_s)
      rescue StandardError
        ::TypeGuessr::Core::Types::Unknown.instance
      end

      # Format method definition signature
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @param param_types [Array<TypeGuessr::Core::Types::Type>] parameter types
      # @param return_type [TypeGuessr::Core::Types::Type] the return type
      # @return [String] formatted signature
      def format_def_signature(parameters, param_types, return_type)
        param_strings = format_parameters(parameters, param_types)
        return_str = ::TypeGuessr::Core::TypeFormatter.format(return_type)

        "**Signature:** `(#{param_strings.join(", ")}) -> #{return_str}`"
      end

      # Format parameters with types
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @param param_types [Array<TypeGuessr::Core::Types::Type>] parameter types
      # @return [Array<String>] formatted parameter strings
      def format_parameters(parameters, param_types)
        return [] if parameters.nil?

        result = []
        type_index = 0

        # Required parameters
        parameters.requireds&.each do |param|
          type_str = ::TypeGuessr::Core::TypeFormatter.format(param_types[type_index])
          result << "#{type_str} #{param.name}"
          type_index += 1
        end

        # Optional parameters
        parameters.optionals&.each do |param|
          type_str = ::TypeGuessr::Core::TypeFormatter.format(param_types[type_index])
          result << "?#{type_str} #{param.name}"
          type_index += 1
        end

        # Keyword parameters
        parameters.keywords&.each do |param|
          type_str = ::TypeGuessr::Core::TypeFormatter.format(param_types[type_index])
          prefix = param.is_a?(Prism::RequiredKeywordParameterNode) ? "" : "?"
          result << "#{param.name}: #{prefix}#{type_str}"
          type_index += 1
        end

        # Rest parameter
        if parameters.rest
          result << "*#{parameters.rest.name || "args"}"
          type_index += 1
        end

        # Keyword rest parameter
        if parameters.keyword_rest
          result << "**#{parameters.keyword_rest.name || "kwargs"}"
          type_index += 1
        end

        # Block parameter
        result << "&#{parameters.block.name || "block"}" if parameters.block

        result
      end
    end
  end
end
