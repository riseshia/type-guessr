# frozen_string_literal: true

require "prism"
require_relative "config"
require_relative "chain_resolver"
require_relative "hover_content_builder"
require_relative "index_adapter"
require_relative "type_matcher"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "../../type_guessr/core/flow_analyzer"
require_relative "../../type_guessr/core/literal_type_analyzer"
require_relative "../../type_guessr/core/def_node_finder"
require_relative "../../type_guessr/core/constant_index"
require_relative "../../type_guessr/core/user_method_return_resolver"
require_relative "../../type_guessr/core/logger"

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
        @chain_resolver = ChainResolver.new(node_context: node_context, global_state: global_state)
        @content_builder = HoverContentBuilder.new(global_state)
        @constant_index = ::TypeGuessr::Core::ConstantIndex.instance

        register_listeners(dispatcher)
      end

      HOVER_NODE_TYPES.each do |node_type|
        define_method(:"on_#{node_type}_node_enter") do |node|
          add_hover_content(node)
        end
      end

      def on_call_node_enter(node)
        return unless node.receiver

        receiver_type = resolve_receiver_chain(node.receiver)
        return if receiver_type == Types::Unknown.instance

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

      def on_def_node_enter(node)
        # 1. Infer parameter types from default values and usage patterns
        param_types = infer_parameter_types(node.parameters, node)

        # 2. Infer return type using FlowAnalyzer
        return_type = infer_return_type(node, param_types)

        # 3. Format and display signature
        signature = format_def_signature(node.parameters, param_types, return_type)
        @response_builder.push(signature, category: :documentation)
      rescue StandardError => e
        # Gracefully handle errors - don't show anything on failure
        ::TypeGuessr::Core::Logger.error("DefNodeHover error", e)
        nil
      end

      # Core layer shortcuts for cleaner code
      Types = ::TypeGuessr::Core::Types
      TypeFormatter = ::TypeGuessr::Core::TypeFormatter
      LiteralTypeAnalyzer = ::TypeGuessr::Core::LiteralTypeAnalyzer
      FlowAnalyzer = ::TypeGuessr::Core::FlowAnalyzer
      DefNodeFinder = ::TypeGuessr::Core::DefNodeFinder
      RBSProvider = ::TypeGuessr::Core::RBSProvider
      UserMethodReturnResolver = ::TypeGuessr::Core::UserMethodReturnResolver
      private_constant :Types, :TypeFormatter, :LiteralTypeAnalyzer, :FlowAnalyzer, :DefNodeFinder, :RBSProvider,
                       :UserMethodReturnResolver

      private

      # RBSProvider singleton instance for querying method signatures
      # @return [TypeGuessr::Core::RBSProvider]
      def rbs_provider
        RBSProvider.instance
      end

      # Cached IndexAdapter instance for accessing RubyIndexer
      # @return [RubyLsp::TypeGuessr::IndexAdapter, nil]
      def index_adapter
        @index_adapter ||= begin
          index = extract_index(@global_state)
          index ? IndexAdapter.new(index) : nil
        end
      end

      # Cached UserMethodReturnResolver instance for user-defined method analysis
      # @return [TypeGuessr::Core::UserMethodReturnResolver, nil]
      def user_method_resolver
        @user_method_resolver ||= begin
          adapter = index_adapter
          adapter ? UserMethodReturnResolver.new(adapter) : nil
        end
      end

      # Extract index from global_state or return nil
      # @param global_state_or_index [Object, nil] either GlobalState (has .index) or RubyIndexer::Index directly
      # @return [RubyIndexer::Index, nil]
      def extract_index(global_state_or_index)
        return nil if global_state_or_index.nil?

        # If it responds to .index, it's a GlobalState
        if global_state_or_index.respond_to?(:index)
          global_state_or_index.index
        else
          # Otherwise assume it's already an index
          global_state_or_index
        end
      end

      def register_listeners(dispatcher)
        # Dynamically generate listener method names from HOVER_NODE_TYPES
        listener_methods = HOVER_NODE_TYPES.map { |node_type| :"on_#{node_type}_node_enter" }
        dispatcher.register(self, *listener_methods)
      end

      # Recursively resolve type for method chain receivers
      # Handles CallNode receivers (e.g., str.chars.first -> resolve "str.chars" type)
      # @param node [Prism::Node] the receiver node to resolve
      # @param depth [Integer] current recursion depth (to prevent infinite loops)
      # @return [Types::Type] the resolved type (Unknown if cannot resolve)
      def resolve_receiver_chain(node, depth = 0)
        return Types::Unknown.instance if depth > 5

        case node
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
          @chain_resolver.resolve(node) || Types::Unknown.instance
        when Prism::CallNode
          # Recursively resolve the base receiver type
          base_type = if node.receiver
                        resolve_receiver_chain(node.receiver, depth + 1)
                      else
                        # No receiver means method call on self
                        infer_self_type || Types::Unknown.instance
                      end

          return Types::Unknown.instance if base_type == Types::Unknown.instance

          # Get the return type of the method call using RBS
          # Check if the call has a block - affects method signature selection
          has_block = !node.block.nil?
          class_name = extract_type_name(base_type)
          method_name = node.name.to_s

          # Get all signatures and select the appropriate one based on block presence
          signatures = rbs_provider.get_method_signatures(class_name, method_name)
          return Types::Unknown.instance if signatures.empty?

          # Select signature based on whether call has a block
          selected_sig = if has_block
                           # Prefer signature with block requirement
                           signatures.find { |sig| sig.method_type.block } || signatures.first
                         else
                           # Prefer signature without block requirement
                           signatures.find { |sig| !sig.method_type.block } || signatures.first
                         end

          return_type = selected_sig.method_type.type.return_type

          # Extract element type for substitution (if receiver is Array)
          substitutions = {}
          substitutions[:Elem] = base_type.element_type if base_type.is_a?(Types::ArrayType) && base_type.element_type

          convert_rbs_type_to_types(return_type, substitutions)
        when Prism::SelfNode
          infer_self_type || Types::Unknown.instance
        else
          Types::Unknown.instance
        end
      end

      def add_hover_content(node)
        block_param_type = try_block_parameter_inference(node)
        if block_param_type
          # Show hover for block parameters (including Unknown type as "untyped")
          type_info = { direct_type: block_param_type, method_calls: [] }
          type_entries = block_param_type.is_a?(Types::ClassInstance) ? get_type_entries_for_types(block_param_type) : {}
          content = @content_builder.build(type_info, matching_types: [], type_entries: type_entries)
          @response_builder.push(content, category: :documentation) if content
          return
        end

        # Handle all parameter types (except block parameters which are handled above)
        parameter_node_types = [
          Prism::RequiredParameterNode, Prism::OptionalParameterNode,
          Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode,
          Prism::RestParameterNode, Prism::KeywordRestParameterNode,
          Prism::BlockParameterNode, Prism::ForwardingParameterNode
        ]

        if parameter_node_types.any? { |type| node.is_a?(type) } && !block_parameter?(node)
          # Find containing method to collect method calls on the parameter
          method_node = find_containing_method(node)
          method_calls = if method_node && node.respond_to?(:name)
                           collect_parameter_method_calls(node.name.to_s, method_node)
                         else
                           []
                         end

          param_type = try_parameter_type_inference(node)
          # For parameters, show content even if type is unknown
          type_to_show = param_type && param_type != Types::Unknown.instance ? param_type : Types::Unknown.instance
          type_info = { direct_type: type_to_show, method_calls: method_calls }

          # Get type entries for linking if it's a ClassInstance
          type_entries = param_type ? get_type_entries_for_types(param_type) : {}

          content = @content_builder.build(type_info, matching_types: [], type_entries: type_entries)
          @response_builder.push(content, category: :documentation) if content
          return
        end

        flow_type = try_flow_analysis(node)
        if flow_type && flow_type != Types::Unknown.instance
          # Build content from flow-inferred type
          type_info = { direct_type: flow_type, method_calls: [] }
          content = @content_builder.build(type_info, matching_types: [], type_entries: {})
          @response_builder.push(content, category: :documentation) if content
          return
        end

        # Handle self node
        if node.is_a?(Prism::SelfNode)
          self_type = infer_self_type
          if self_type
            type_info = { direct_type: self_type, method_calls: [] }
            type_entries = self_type.is_a?(Types::ClassInstance) ? get_type_entries_for_types(self_type) : {}
            content = @content_builder.build(type_info, matching_types: [], type_entries: type_entries)
            @response_builder.push(content, category: :documentation) if content
          end
          return
        end

        # Fallback to ChainResolver
        resolved_type = @chain_resolver.resolve(node)
        return if !resolved_type

        # Collect method calls for debug display (for local variables)
        method_calls = []
        if node.is_a?(Prism::LocalVariableReadNode)
          method_node = find_containing_method(node)
          method_calls = collect_parameter_method_calls(node.name.to_s, method_node) if method_node
        end

        # Build type_info structure for content builder (including Unknown types for parameters)
        type_info = { direct_type: resolved_type, method_calls: method_calls }

        # Get entries for linking to type definitions
        type_entries = {}
        if resolved_type.is_a?(Types::ClassInstance)
          index = extract_index(@global_state)
          if index
            adapter = IndexAdapter.new(index)
            entries = adapter.resolve_constant(resolved_type.name)
            type_entries[resolved_type] = entries.first if entries&.any?
          end
        end

        content = @content_builder.build(type_info, matching_types: [], type_entries: type_entries)
        @response_builder.push(content, category: :documentation) if content
      end

      # Extract type name from a Types object
      # @param type_obj [TypeGuessr::Core::Types::Type] the type object
      # @return [String] the type name
      def extract_type_name(type_obj)
        case type_obj
        when Types::ClassInstance
          type_obj.name
        when Types::ArrayType
          "Array"
        when Types::HashShape
          "Hash"
        else
          TypeFormatter.format(type_obj)
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

        "**Method:** `#{method_name}`\n\n**RBS Signatures:**\n```ruby\n#{sig_strings.join("\n")}\n```"
      end

      # Infer parameter types from default values and usage patterns
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @param def_node [Prism::DefNode] the method definition node
      # @return [Array<TypeGuessr::Core::Types::Type>] array of parameter types
      def infer_parameter_types(parameters, def_node)
        return [] if parameters.nil?

        all_params = []
        all_params.concat(parameters.requireds) if parameters.requireds
        all_params.concat(parameters.optionals) if parameters.optionals
        all_params.concat(parameters.keywords) if parameters.keywords
        all_params << parameters.rest if parameters.rest
        all_params << parameters.keyword_rest if parameters.keyword_rest
        all_params << parameters.block if parameters.block

        all_params.compact.map do |param|
          infer_single_parameter_type(param, def_node)
        end
      end

      # Infer type for a single parameter
      # @param param [Prism::Node] the parameter node
      # @param def_node [Prism::DefNode] the method definition node
      # @return [TypeGuessr::Core::Types::Type] the inferred type
      def infer_single_parameter_type(param, def_node)
        case param
        when Prism::OptionalParameterNode, Prism::OptionalKeywordParameterNode
          # Infer from default value
          if param.value
            analyze_value_type_for_param(param.value) || Types::Unknown.instance
          else
            Types::Unknown.instance
          end
        when Prism::RequiredParameterNode, Prism::RequiredKeywordParameterNode
          infer_parameter_type_from_usage(param, def_node)
        else
          # Rest, block → untyped
          Types::Unknown.instance
        end
      end

      # Analyze value type for parameter (reuse existing logic)
      # @param node [Prism::Node] the value node
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type
      def analyze_value_type_for_param(node)
        # Try literal type inference first
        type = LiteralTypeAnalyzer.infer(node)
        return type if type

        # Handle .new calls
        if node.is_a?(Prism::CallNode) && node.name == :new && node.receiver
          class_name = extract_class_name_from_new_call(node.receiver)
          return Types::ClassInstance.new(class_name) if class_name
        end

        nil
      end

      # Extract class name from .new call receiver
      # @param receiver [Prism::Node] the receiver node
      # @return [String, nil] the class name or nil
      def extract_class_name_from_new_call(receiver)
        case receiver
        when Prism::ConstantReadNode
          name = receiver.name.to_s

          resolved = @constant_index.resolve_alias(name)
          resolved || name
        when Prism::ConstantPathNode
          path = receiver.slice

          resolved = @constant_index.resolve_alias(path)
          resolved || path
        end
      end

      # @param param [Prism::Node] the parameter node
      # @param def_node [Prism::DefNode] the method definition node
      # @return [TypeGuessr::Core::Types::Type] the inferred type
      def infer_parameter_type_from_usage(param, def_node)
        param_name = param.name.to_s

        # Collect method calls on this parameter from method body
        method_calls = collect_parameter_method_calls(param_name, def_node)

        # No method calls → can't infer
        return Types::Unknown.instance if method_calls.empty?

        # Use TypeMatcher to find candidate types
        matching_types = infer_type_from_methods(method_calls)

        # No matches or truncated → Unknown
        return Types::Unknown.instance if matching_types.empty?
        return Types::Unknown.instance if matching_types.last == TypeMatcher::TRUNCATED_MARKER

        # Exactly one match → use it
        return matching_types.first if matching_types.size == 1

        # Multiple matches → create Union
        Types::Union.new(matching_types)
      rescue StandardError => e
        ::TypeGuessr::Core::Logger.error("Parameter type inference error", e)
        Types::Unknown.instance
      end

      # Collect method calls on a parameter from method body
      # @param param_name [String] the parameter name
      # @param def_node [Prism::DefNode] the method definition node
      # @return [Array<String>] array of method names called on the parameter
      def collect_parameter_method_calls(param_name, def_node)
        return [] unless def_node.body

        calls = []
        visitor = ParameterMethodCallVisitor.new(param_name, calls)
        def_node.body.accept(visitor)
        calls.uniq
      end

      # Visitor to collect method calls on a specific variable
      class ParameterMethodCallVisitor < Prism::Visitor
        def initialize(var_name, calls_collector)
          @var_name = var_name
          @calls = calls_collector
          super()
        end

        def visit_call_node(node)
          # Check if receiver is our target variable
          @calls << node.name.to_s if node.receiver.is_a?(Prism::LocalVariableReadNode) && node.receiver.name.to_s == @var_name

          # Continue traversing
          super
        end
      end

      # Infer return type using FlowAnalyzer
      # @param node [Prism::DefNode] the method definition node
      # @param param_types [Array<TypeGuessr::Core::Types::Type>] parameter types
      # @return [TypeGuessr::Core::Types::Type] the inferred return type
      def infer_return_type(node, param_types = [])
        source = node.slice

        # Build initial types from parameters
        initial_types = build_initial_types_from_parameters(node.parameters, param_types)

        # Create analyzer with initial types
        analyzer = FlowAnalyzer.new(initial_types: initial_types)
        result = analyzer.analyze(source)
        result.return_type_for_method(node.name.to_s)
      rescue StandardError
        Types::Unknown.instance
      end

      # Build initial type map from parameters
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @param param_types [Array<TypeGuessr::Core::Types::Type>] parameter types
      # @return [Hash{String => TypeGuessr::Core::Types::Type}] map of parameter names to types
      def build_initial_types_from_parameters(parameters, param_types)
        return {} if parameters.nil? || param_types.empty?

        initial_types = {}
        type_index = 0

        # Required parameters
        parameters.requireds&.each do |param|
          initial_types[param.name.to_s] = param_types[type_index] if type_index < param_types.size
          type_index += 1
        end

        # Optional parameters
        parameters.optionals&.each do |param|
          initial_types[param.name.to_s] = param_types[type_index] if type_index < param_types.size
          type_index += 1
        end

        # Keyword parameters
        parameters.keywords&.each do |param|
          initial_types[param.name.to_s] = param_types[type_index] if type_index < param_types.size
          type_index += 1
        end

        # Rest, keyword rest, and block parameters are not added to initial types
        # as they're typically Unknown or not useful for flow analysis

        initial_types
      end

      # Format method definition signature
      # @param parameters [Prism::ParametersNode, nil] the parameters node
      # @param param_types [Array<TypeGuessr::Core::Types::Type>] parameter types
      # @param return_type [TypeGuessr::Core::Types::Type] the return type
      # @return [String] formatted signature
      def format_def_signature(parameters, param_types, return_type)
        param_strings = format_parameters(parameters, param_types)
        return_str = TypeFormatter.format(return_type)

        "**Guessed Signature:** `(#{param_strings.join(", ")}) -> #{return_str}`"
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
          type_str = TypeFormatter.format(param_types[type_index])
          result << "#{type_str} #{param.name}"
          type_index += 1
        end

        # Optional parameters
        parameters.optionals&.each do |param|
          type_str = TypeFormatter.format(param_types[type_index])
          result << "?#{type_str} #{param.name}"
          type_index += 1
        end

        # Keyword parameters
        parameters.keywords&.each do |param|
          type_str = TypeFormatter.format(param_types[type_index])
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

      # @param node [Prism::RequiredParameterNode, Prism::RequiredKeywordParameterNode] the parameter node
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type or nil
      def try_parameter_type_inference(node)
        # Find the containing method definition
        method_node = find_containing_method(node)
        return nil unless method_node

        # Infer type from usage
        infer_parameter_type_from_usage(node, method_node)
      rescue StandardError => e
        ::TypeGuessr::Core::Logger.error("Parameter type inference error", e)
        nil
      end

      # Try to infer block parameter type from surrounding call context
      # @param node [Prism::Node] the node to analyze
      # @return [TypeGuessr::Core::Types::Type, nil] the inferred type or nil
      def try_block_parameter_inference(node)
        # Only handle block parameters (RequiredParameterNode inside a block)
        return nil unless node.is_a?(Prism::RequiredParameterNode)

        # Check if this is actually a block parameter (not a method parameter)
        return nil unless block_parameter?(node)

        # Check if we have a surrounding CallNode via node_context
        call_node = @node_context.call_node
        return Types::Unknown.instance unless call_node

        # Get the receiver type using chain resolution
        receiver_type = if call_node.receiver
                          resolve_receiver_chain(call_node.receiver)
                        else
                          infer_self_type || Types::Unknown.instance
                        end

        return Types::Unknown.instance if receiver_type == Types::Unknown.instance

        # Get block parameter types from RBS with substitution
        method_name = call_node.name.to_s

        # Determine the class name for RBS lookup
        # Special case: if receiver is a CallNode without block (e.g., arr.map),
        # it likely returns an Enumerator, so use "Enumerator" for RBS lookup
        class_name = if call_node.receiver.is_a?(Prism::CallNode) && call_node.receiver.block.nil?
                       "Enumerator"
                     else
                       extract_type_name(receiver_type)
                     end

        # Extract element type for substitution (if ArrayType)
        elem_type = receiver_type.is_a?(Types::ArrayType) ? receiver_type.element_type : nil

        # Extract key and value types for HashShape
        key_type = nil
        value_type = nil

        if receiver_type.is_a?(Types::HashShape)
          key_type = Types::ClassInstance.new("Symbol")
          field_types = receiver_type.fields.values
          value_type = field_types.size == 1 ? field_types.first : Types::Union.new(field_types)
        end

        block_param_types = rbs_provider.get_block_param_types_with_substitution(
          class_name,
          method_name,
          elem: elem_type,
          key: key_type,
          value: value_type
        )

        return nil if block_param_types.empty?

        # Find the index of this parameter in the block
        param_index = find_block_param_index(node)
        return nil if param_index.nil?

        # Handle tuple destructuring (e.g., Hash#each with |k, v|)
        # RBS defines Hash#each as: () { ([K, V]) -> void } -> self
        # Ruby destructures [K, V] into separate parameters |k, v|
        if block_param_types.size == 1 && block_param_types.first.is_a?(Types::ArrayType)
          tuple_type = block_param_types.first
          if tuple_type.element_type.is_a?(Types::Union)
            union_types = tuple_type.element_type.types

            # Count the actual number of block parameters
            call_node = @node_context.call_node
            block_node = call_node&.block
            num_params = if block_node.is_a?(Prism::BlockNode) && block_node.parameters
                           block_node.parameters.parameters&.requireds&.size || 0
                         else
                           0
                         end

            # For Hash#each with |k, v| (2 params) and union [Symbol, String, Integer] (3 types):
            # param 0 (k) -> union[0] = Symbol
            # param 1 (v) -> Union[union[1], union[2]] = Union[String, Integer]
            result = if num_params == 2 && param_index == 1 && union_types.size > 2
                       # Reconstruct union for remaining types
                       remaining_types = union_types[1..]
                       remaining_types.size == 1 ? remaining_types.first : Types::Union.new(remaining_types)
                     elsif param_index < union_types.size
                       union_types[param_index]
                     end

            return result
          end
        end

        return nil if param_index >= block_param_types.size

        block_param_types[param_index]
      rescue StandardError => e
        ::TypeGuessr::Core::Logger.error("BlockParam inference error", e)
        nil
      end

      # Find the index of a block parameter in its block
      # Check if a parameter node is a block parameter
      # @param node [Prism::Node] the parameter node
      # @return [Boolean] true if this is a block parameter
      def block_parameter?(node)
        return false unless node.is_a?(Prism::RequiredParameterNode)

        call_node = @node_context.call_node
        return false unless call_node

        block_node = call_node.block
        return false unless block_node.is_a?(Prism::BlockNode)

        block_params = block_node.parameters
        return false unless block_params

        params_node = block_params.parameters
        return false unless params_node

        # Check if this parameter is in the block's parameter list
        params_node.requireds.any? { |p| p.name == node.name }
      end

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
        ::TypeGuessr::Core::Logger.debug("FlowAnalyzer: trying for variable #{var_name}")

        # Find the containing method definition
        method_node = find_containing_method(node)

        # If no containing method, try analyzing the entire file (top-level code)
        unless method_node
          ::TypeGuessr::Core::Logger.debug("FlowAnalyzer: no containing method, trying top-level")
          source_object = node.location.__send__(:source)
          source = source_object.source
          analyzer = FlowAnalyzer.new
          result = analyzer.analyze(source)

          # Use absolute line number for top-level code
          inferred_type = result.type_at(node.location.start_line, node.location.start_column, var_name)
          ::TypeGuessr::Core::Logger.debug("FlowAnalyzer: inferred type (top-level) = #{inferred_type.inspect}")
          return inferred_type
        end

        # Analyze the method body
        source = method_node.slice
        analyzer = FlowAnalyzer.new
        result = analyzer.analyze(source)

        # Calculate relative line number within the method slice
        # FlowAnalyzer uses 1-based line numbers relative to the sliced source
        relative_line = node.location.start_line - method_node.location.start_line + 1
        inferred_type = result.type_at(relative_line, node.location.start_column, var_name)
        ::TypeGuessr::Core::Logger.debug("FlowAnalyzer: inferred type = #{inferred_type.inspect}")
        inferred_type
      rescue StandardError => e
        ::TypeGuessr::Core::Logger.error("FlowAnalyzer error", e)
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

        ::TypeGuessr::Core::Logger.debug("Finding method containing line #{target_line}, col #{target_column}")

        # Parse the full source
        parsed = Prism.parse(source_code)

        # Find the DefNode that contains this position
        finder = DefNodeFinder.new(target_line, target_column)
        parsed.value.accept(finder)

        ::TypeGuessr::Core::Logger.debug("Found method: #{finder.result&.name}") if finder.result
        ::TypeGuessr::Core::Logger.debug("No containing method found") unless finder.result

        finder.result
      rescue StandardError => e
        ::TypeGuessr::Core::Logger.error("find_containing_method error", e)
        nil
      end

      # Get type entries for linking to type definitions
      # @param type [Types::Type] the type to get entries for
      # @return [Hash] map of type to entry
      def get_type_entries_for_types(type)
        type_entries = {}
        index = extract_index(@global_state)
        return type_entries unless index

        adapter = IndexAdapter.new(index)

        case type
        when Types::ClassInstance
          entries = adapter.resolve_constant(type.name)
          type_entries[type] = entries.first if entries&.any?
        when Types::Union
          type.types.each do |t|
            next unless t.is_a?(Types::ClassInstance)

            entries = adapter.resolve_constant(t.name)
            type_entries[t] = entries.first if entries&.any?
          end
        end

        type_entries
      end

      # Infer types from method calls using TypeMatcher
      # @param method_calls [Array<String>] method names
      # @return [Array<Types::Type>] matching types
      def infer_type_from_methods(method_calls)
        return [] if method_calls.empty?

        index = extract_index(@global_state)
        return [] unless index

        matcher = TypeMatcher.new(index)
        matcher.find_matching_types(method_calls)
      end

      # Convert RBS type to our Types system (simplified version)
      # @param rbs_type [RBS::Types::t] the RBS type
      # @param substitutions [Hash] type variable substitutions (e.g., { Elem: Integer })
      # @return [Types::Type] our type representation
      def convert_rbs_type_to_types(rbs_type, substitutions = {})
        case rbs_type
        when RBS::Types::ClassInstance
          class_name = rbs_type.name.to_s.delete_prefix("::")

          # Handle Array with type parameter
          if class_name == "Array" && rbs_type.args.size == 1
            element_type = convert_rbs_type_to_types(rbs_type.args.first, substitutions)
            return Types::ArrayType.new(element_type)
          end

          # Handle Enumerator with type parameter
          # Enumerator[Elem, Return] -> we care about Elem (the element type)
          # Temporarily use ArrayType to preserve element_type info (TODO: add EnumeratorType)
          if class_name == "Enumerator" && rbs_type.args.size >= 1
            element_type = convert_rbs_type_to_types(rbs_type.args.first, substitutions)
            return Types::ArrayType.new(element_type)
          end

          # For other generic types, just return ClassInstance
          Types::ClassInstance.new(class_name)
        when RBS::Types::Union
          types = rbs_type.types.map { |t| convert_rbs_type_to_types(t, substitutions) }
          Types::Union.new(types)
        when RBS::Types::Variable
          # Type variable (e.g., Elem, U) - check substitutions first
          substitutions[rbs_type.name] || Types::Unknown.instance
        else
          Types::Unknown.instance
        end
      end

      # Infer type for self node
      # @return [Types::Type, nil] the inferred type for self
      def infer_self_type
        nesting = @node_context.nesting
        return nil if nesting.empty?

        # Get the innermost class/module from nesting
        innermost = nesting.last
        class_name = if innermost.respond_to?(:name)
                       innermost.name.to_s
                     else
                       innermost.to_s
                     end

        return nil if class_name.empty?

        Types::ClassInstance.new(class_name)
      end
    end
  end
end
