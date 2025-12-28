# frozen_string_literal: true

require_relative "config"
require_relative "type_matcher"
require_relative "../../type_guessr/core/literal_type_analyzer"

module RubyLsp
  module TypeGuessr
    # Resolves types for method call chains recursively
    # Coordinates between RBSProvider, UserMethodReturnResolver, and VariableTypeResolver
    class CallChainResolver
      # Core layer shortcuts
      Types = ::TypeGuessr::Core::Types
      LiteralTypeAnalyzer = ::TypeGuessr::Core::LiteralTypeAnalyzer
      private_constant :Types, :LiteralTypeAnalyzer

      def initialize(type_resolver:, rbs_provider:, user_method_resolver: nil)
        @type_resolver = type_resolver
        @rbs_provider = rbs_provider
        @user_method_resolver = user_method_resolver
      end

      # Resolve receiver type recursively for method chains
      # Supports: variables, CallNode chains, and literals
      # @param receiver [Prism::Node] the receiver node
      # @param depth [Integer] current recursion depth (for safety)
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve(receiver, depth: 0)
        # Depth limit to prevent infinite recursion
        return nil if depth > Config::MAX_CHAIN_DEPTH

        case receiver
        when Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode, Prism::ClassVariableReadNode
          # Delegate to existing variable resolver
          resolve_variable_type(receiver)
        when Prism::CallNode
          # Recursive: resolve receiver, then get method return type
          resolve_call_chain(receiver, depth)
        else
          # Try literal type inference
          LiteralTypeAnalyzer.infer(receiver)
        end
      end

      private

      # Resolve a call chain by getting receiver type and method return type
      # @param node [Prism::CallNode] the call node
      # @param depth [Integer] current recursion depth
      # @return [TypeGuessr::Core::Types::Type, nil] the resolved type or nil
      def resolve_call_chain(node, depth)
        return nil unless node.receiver

        # 1. Get receiver type (recursive)
        receiver_type = resolve(node.receiver, depth: depth + 1)

        # 2. Phase 6: If receiver is Unknown, try heuristic inference
        if receiver_type.nil? || receiver_type == Types::Unknown.instance
          receiver_type = try_heuristic_type_inference(node.receiver)
          return nil if receiver_type.nil? || receiver_type == Types::Unknown.instance
        end

        # 3. Get method return type from RBS
        type = @rbs_provider.get_method_return_type(extract_type_name(receiver_type), node.name.to_s)

        # 4. Phase 10: If RBS returns Unknown, try user-defined method analysis
        if type == Types::Unknown.instance && @user_method_resolver
          type = @user_method_resolver.get_return_type(
            extract_type_name(receiver_type),
            node.name.to_s
          )
        end

        type
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
        Types::Union.new(types_only)
      rescue StandardError => e
        warn "Heuristic inference error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        nil
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
        else
          ::TypeGuessr::Core::TypeFormatter.format(type_obj)
        end
      end
    end
  end
end
