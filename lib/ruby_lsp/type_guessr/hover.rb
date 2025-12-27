# frozen_string_literal: true

require "prism"
require_relative "variable_type_resolver"
require_relative "hover_content_builder"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "../../type_guessr/core/flow_analyzer"
require_relative "../../type_guessr/core/literal_type_analyzer"
require_relative "../../type_guessr/core/def_node_finder"

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
        @node_context = node_context
        @global_state = global_state
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

        # Phase 5.2b: Resolve receiver type recursively for method chains
        receiver_type = resolve_receiver_type_recursively(node.receiver)
        return if receiver_type.nil? || receiver_type == ::TypeGuessr::Core::Types::Unknown.instance

        # 2. Query RBS signatures
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

      # Cached RBSProvider instance for querying method signatures
      # @return [TypeGuessr::Core::RBSProvider]
      def rbs_provider
        @rbs_provider ||= ::TypeGuessr::Core::RBSProvider.new
      end

      def register_listeners(dispatcher)
        # Dynamically generate listener method names from HOVER_NODE_TYPES
        listener_methods = HOVER_NODE_TYPES.map { |node_type| :"on_#{node_type}_node_enter" }
        dispatcher.register(self, *listener_methods)
      end

      def add_hover_content(node)
        # Phase 8.3: Try block parameter type inference
        block_param_type = try_block_parameter_inference(node)
        if block_param_type && block_param_type != ::TypeGuessr::Core::Types::Unknown.instance
          type_info = { direct_type: block_param_type, method_calls: [] }
          content = @content_builder.build(type_info, matching_types: [], type_entries: {})
          @response_builder.push(content, category: :documentation) if content
          return
        end

        # Phase 5.4: Try FlowAnalyzer first for local variables
        flow_type = try_flow_analysis(node)
        if flow_type && flow_type != ::TypeGuessr::Core::Types::Unknown.instance
          # Build content from flow-inferred type
          type_info = { direct_type: flow_type, method_calls: [] }
          content = @content_builder.build(type_info, matching_types: [], type_entries: {})
          @response_builder.push(content, category: :documentation) if content
          return
        end

        # Fallback to existing VariableTypeResolver
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

      # Resolve receiver type recursively for method chains
      # Supports: variables, CallNode chains, and literals
      # @param receiver [Prism::Node] the receiver node
      # @param depth [Integer] current recursion depth (for safety)
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve_receiver_type_recursively(receiver, depth: 0)
        # Depth limit to prevent infinite recursion
        return nil if depth > 5

        case receiver
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
          # Delegate to existing variable resolver
          resolve_variable_type(receiver)
        when Prism::CallNode
          # Recursive: resolve receiver, then get method return type
          resolve_call_chain(receiver, depth)
        else
          # Try literal type inference
          ::TypeGuessr::Core::LiteralTypeAnalyzer.infer(receiver)
        end
      end

      # Resolve a call chain by getting receiver type and method return type
      # @param node [Prism::CallNode] the call node
      # @param depth [Integer] current recursion depth
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve_call_chain(node, depth)
        return nil unless node.receiver

        # 1. Get receiver type (recursive)
        receiver_type = resolve_receiver_type_recursively(node.receiver, depth: depth + 1)

        # 2. Phase 6: If receiver is Unknown, try heuristic inference
        if receiver_type.nil? || receiver_type == ::TypeGuessr::Core::Types::Unknown.instance
          receiver_type = try_heuristic_type_inference(node.receiver)
          return nil if receiver_type.nil? || receiver_type == ::TypeGuessr::Core::Types::Unknown.instance
        end

        # 3. Get method return type from RBS
        rbs_provider.get_method_return_type(extract_type_name(receiver_type), node.name.to_s)
      end

      # Resolve variable type using existing VariableTypeResolver
      # @param node [Prism::Node] the variable node
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve_variable_type(receiver)
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
        when ::TypeGuessr::Core::Types::ArrayType
          "Array"
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
        # Try literal type inference first
        type = ::TypeGuessr::Core::LiteralTypeAnalyzer.infer(node)
        return type if type

        # Handle .new calls
        if node.is_a?(Prism::CallNode) && node.name == :new && node.receiver
          class_name = extract_class_name_from_new_call(node.receiver)
          return ::TypeGuessr::Core::Types::ClassInstance.new(class_name) if class_name
        end

        nil
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

      # Try to infer receiver type using method-call set heuristic (Phase 6)
      # @param receiver [Prism::Node] the receiver node
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type or nil
      def try_heuristic_type_inference(receiver)
        # Only try for variable nodes
        return nil unless receiver.is_a?(Prism::LocalVariableReadNode) ||
                          receiver.is_a?(Prism::InstanceVariableReadNode) ||
                          receiver.is_a?(Prism::ClassVariableReadNode)

        # Get type info from VariableTypeResolver
        type_info = @type_resolver.resolve_type(receiver)
        return nil unless type_info

        # If no method calls tracked, can't infer
        method_calls = type_info[:method_calls]
        return nil if method_calls.nil? || method_calls.empty?

        # Use TypeMatcher to find types with all these methods
        matching_types = @type_resolver.infer_type_from_methods(method_calls)
        return nil if matching_types.empty?

        # If exactly one type matches, use it
        return matching_types.first if matching_types.size == 1

        # If multiple types match, create a Union
        # Filter out truncation marker
        types_only = matching_types.reject { |t| t == TypeMatcher::TRUNCATED_MARKER }
        return nil if types_only.empty?

        # Return Union for multiple matches
        ::TypeGuessr::Core::Types::Union.new(types_only)
      rescue StandardError => e
        warn "Heuristic inference error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        nil
      end

      # Try to infer block parameter type from surrounding call context
      # @param node [Prism::Node] the node to analyze
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type or nil
      def try_block_parameter_inference(node)
        # Only handle block parameters (RequiredParameterNode inside a block)
        return nil unless node.is_a?(Prism::RequiredParameterNode)

        # Check if we have a surrounding CallNode via node_context
        call_node = @node_context.call_node
        return nil unless call_node

        warn "BlockParam: found call_node #{call_node.name}" if ENV["DEBUG"]

        # Get the receiver type
        receiver_type = resolve_receiver_type_recursively(call_node.receiver)
        return nil if receiver_type.nil? || receiver_type == ::TypeGuessr::Core::Types::Unknown.instance

        warn "BlockParam: receiver_type = #{receiver_type.inspect}" if ENV["DEBUG"]

        # Get block parameter types from RBS with substitution
        method_name = call_node.name.to_s
        class_name = extract_type_name(receiver_type)

        # Extract element type for substitution (if ArrayType)
        elem_type = receiver_type.is_a?(::TypeGuessr::Core::Types::ArrayType) ? receiver_type.element_type : nil

        block_param_types = rbs_provider.get_block_param_types_with_substitution(
          class_name,
          method_name,
          elem: elem_type
        )

        return nil if block_param_types.empty?

        # Find the index of this parameter in the block
        param_index = find_block_param_index(node)
        return nil if param_index.nil? || param_index >= block_param_types.size

        block_param_types[param_index]
      rescue StandardError => e
        warn "BlockParam inference error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        nil
      end

      # Find the index of a block parameter in its block
      # @param node [Prism::RequiredParameterNode] the parameter node
      # @return [Integer, nil] the parameter index or nil
      def find_block_param_index(node)
        # Get the call_node and its block
        call_node = @node_context.call_node
        return nil unless call_node

        block_node = call_node.block
        return nil unless block_node.is_a?(Prism::BlockNode)

        block_params = block_node.parameters
        return nil unless block_params

        params_node = block_params.parameters
        return nil unless params_node

        # Find the index by matching the parameter name
        # (Using .equal? doesn't work since we may have different node instances)
        params_node.requireds.index { |p| p.name == node.name }
      end

      # Try to analyze type using FlowAnalyzer
      # @param node [Prism::Node] the node to analyze
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type or nil
      def try_flow_analysis(node)
        # Only analyze local variable reads
        return nil unless node.is_a?(Prism::LocalVariableReadNode)

        # Extract variable name
        var_name = node.name.to_s
        warn "FlowAnalyzer: trying for variable #{var_name}" if ENV["DEBUG"]

        # Find the containing method definition
        method_node = find_containing_method(node)
        unless method_node
          warn "FlowAnalyzer: no containing method found" if ENV["DEBUG"]
          return nil
        end

        # Analyze the method body
        source = method_node.slice
        analyzer = ::TypeGuessr::Core::FlowAnalyzer.new
        result = analyzer.analyze(source)

        # Query type at the node's line for the specific variable
        # Note: FlowAnalyzer uses 1-based line numbers
        inferred_type = result.type_at(node.location.start_line, node.location.start_column, var_name)
        warn "FlowAnalyzer: inferred type = #{inferred_type.inspect}" if ENV["DEBUG"]
        inferred_type
      rescue StandardError => e
        warn "FlowAnalyzer: error #{e.class}: #{e.message}" if ENV["DEBUG"]
        # Fall back to existing resolver on any error
        nil
      end

      # Find the containing method definition node
      # @param node [Prism::Node] the starting node
      # @return [Prism::DefNode, nil] the method node or nil
      def find_containing_method(node)
        # Get the full source from the node's location using __send__ to access protected method
        source_object = node.location.__send__(:source)
        source_code = source_object.source
        target_line = node.location.start_line
        target_column = node.location.start_column

        warn "Finding method containing line #{target_line}, col #{target_column}" if ENV["DEBUG"]

        # Parse the full source
        parsed = Prism.parse(source_code)

        # Find the DefNode that contains this position
        finder = ::TypeGuessr::Core::DefNodeFinder.new(target_line, target_column)
        parsed.value.accept(finder)

        warn "Found method: #{finder.result&.name}" if ENV["DEBUG"] && finder.result
        warn "No containing method found" if ENV["DEBUG"] && !finder.result

        finder.result
      rescue StandardError => e
        warn "find_containing_method error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        warn e.backtrace.join("\n") if ENV["DEBUG"]
        nil
      end
    end
  end
end
