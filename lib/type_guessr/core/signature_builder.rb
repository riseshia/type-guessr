# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # Builds MethodSignature from DefNode using Resolver for type inference.
    # Extracts the param formatting + type inference logic that was previously
    # embedded in the LSP hover layer, making it reusable across contexts.
    class SignatureBuilder
      def initialize(resolver)
        @resolver = resolver
      end

      # @param def_node [IR::DefNode] Method definition node
      # @return [Types::MethodSignature] Structured method signature
      def build_from_def_node(def_node)
        params = build_param_signatures(def_node.params)
        return_type = @resolver.infer(def_node).type
        Types::MethodSignature.new(params, return_type)
      end

      private

      def build_param_signatures(param_nodes)
        return [] if param_nodes.nil? || param_nodes.empty?

        param_nodes.map { |p| build_param_signature(p) }
      end

      def build_param_signature(param_node)
        type = @resolver.infer(param_node).type
        Types::ParamSignature.new(
          name: param_node.name,
          kind: param_node.kind,
          type: type
        )
      end
    end
  end
end
