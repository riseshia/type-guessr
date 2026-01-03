# frozen_string_literal: true

require_relative "../../type_guessr/core/chain_context"
require_relative "../../type_guessr/core/chain_index"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "../../type_guessr/core/scope_resolver"
require_relative "type_matcher"

module RubyLsp
  module TypeGuessr
    # Resolves variable types using Chain-based lazy evaluation
    # Replaces VariableTypeResolver and CallChainResolver
    class ChainResolver
      Types = ::TypeGuessr::Core::Types
      ChainContext = ::TypeGuessr::Core::ChainContext
      ChainIndex = ::TypeGuessr::Core::ChainIndex
      ScopeResolver = ::TypeGuessr::Core::ScopeResolver

      def initialize(node_context:, global_state:)
        @node_context = node_context
        @global_state = global_state
        @chain_index = ChainIndex.instance
        @rbs_provider = ::TypeGuessr::Core::RBSProvider.instance
        @type_matcher = create_type_matcher
      end

      # Resolve type for a variable node
      # @param node [Prism::Node] variable node to resolve
      # @param file_path [String, nil] optional file path for more precise lookup
      # @return [Types::Type, nil] resolved type or nil
      def resolve(node, file_path: nil)
        var_name = extract_variable_name(node)
        return nil unless var_name

        scope_type = ScopeResolver.determine_scope_type(var_name)
        scope_id = generate_scope_id(scope_type)
        hover_line = node.location.start_line

        context = ChainContext.new(
          chain_index: @chain_index,
          rbs_provider: @rbs_provider,
          type_matcher: @type_matcher,
          user_method_resolver: nil, # TODO: Implement UserMethodResolver
          scope_type: scope_type,
          scope_id: scope_id,
          file_path: file_path,
          max_line: hover_line
        )

        chain = context.lookup_chain(var_name)

        # If no chain found, try heuristic inference or return Unknown
        if !chain
          heuristic_type = try_heuristic_inference(var_name, scope_type, scope_id, hover_line, file_path, context)
          return heuristic_type if heuristic_type != Types::Unknown.instance

          # For variables with no chain (e.g., parameters), return Unknown instead of nil
          return Types::Unknown.instance
        end

        resolved_type = chain.resolve(context)

        # If resolution failed, try heuristic inference
        if resolved_type == Types::Unknown.instance
          heuristic_type = try_heuristic_inference(var_name, scope_type, scope_id, hover_line, file_path, context)
          resolved_type = heuristic_type if heuristic_type != Types::Unknown.instance
        end

        # Return the resolved type (including Unknown for parameters without type info)
        resolved_type
      end

      private

      # Try heuristic inference based on method calls
      def try_heuristic_inference(var_name, scope_type, scope_id, hover_line, file_path, context)
        # Get method calls from index
        method_calls = collect_method_calls(var_name, scope_type, scope_id, hover_line, file_path)
        return Types::Unknown.instance if method_calls.empty?

        matching_types = context.find_matching_types(method_calls)
        return Types::Unknown.instance if matching_types.empty?

        # Filter out TRUNCATED_MARKER
        types_only = matching_types.reject { |t| t == TypeMatcher::TRUNCATED_MARKER }
        return Types::Unknown.instance if types_only.empty?

        types_only.size == 1 ? types_only.first : Types::Union.new(types_only)
      end

      # Collect method calls for a variable
      def collect_method_calls(var_name, scope_type, scope_id, hover_line, file_path)
        # Find all definitions matching the exact scope
        definitions = @chain_index.find_definitions(
          var_name: var_name,
          file_path: file_path,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # Find the closest definition before hover_line
        best_match = definitions
                     .select { |d| d[:def_line] <= hover_line }
                     .max_by { |d| d[:def_line] }

        return [] unless best_match

        # Get method calls for this definition
        calls = @chain_index.get_method_calls(
          file_path: best_match[:file_path],
          scope_type: best_match[:scope_type],
          scope_id: best_match[:scope_id],
          var_name: var_name,
          def_line: best_match[:def_line],
          def_column: best_match[:def_column]
        )

        calls.map { |call| call[:method] }.uniq
      end

      # Extract variable name from node
      def extract_variable_name(node)
        case node
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
          node.name.to_s
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::ClassVariableWriteNode
          node.name.to_s
        when Prism::LocalVariableTargetNode, Prism::InstanceVariableTargetNode, Prism::ClassVariableTargetNode
          node.name.to_s
        when Prism::CallNode
          # For CallNode, extract the receiver if it's a variable
          return nil unless node.receiver

          case node.receiver
          when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
            node.receiver.name.to_s
          end
        end
      end

      # Generate scope ID for current context
      def generate_scope_id(scope_type)
        nesting = @node_context.nesting
        class_path = nesting.map { |n| n.respond_to?(:name) ? n.name : n.to_s }.join("::")

        # Use surrounding_method for the enclosing method name (not call_node which is the method being called)
        method_name = @node_context.surrounding_method&.to_s

        ScopeResolver.generate_scope_id(scope_type, class_path: class_path, method_name: method_name)
      end

      # Create TypeMatcher instance
      def create_type_matcher
        TypeMatcher.new(@global_state.index)
      end
    end
  end
end
