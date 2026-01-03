# frozen_string_literal: true

module TypeGuessr
  module Core
    # Context for chain resolution - provides access to indexes and resolvers
    # Tracks resolution depth to prevent infinite recursion
    class ChainContext
      attr_reader :scope_type, :scope_id, :max_line, :depth, :file_path

      MAX_DEPTH = 5 # Depth limit for method signature inference

      def initialize(
        chain_index:,
        rbs_provider:,
        type_matcher: nil,
        user_method_resolver: nil,
        scope_type: :local_variables,
        scope_id: "(top-level)",
        file_path: nil,
        max_line: Float::INFINITY,
        depth: 0
      )
        @chain_index = chain_index
        @rbs_provider = rbs_provider
        @type_matcher = type_matcher
        @user_method_resolver = user_method_resolver
        @scope_type = scope_type
        @scope_id = scope_id
        @file_path = file_path
        @max_line = max_line
        @depth = depth
      end

      # Create child context with incremented depth
      # Returns nil if depth limit exceeded
      # @param new_scope_type [Symbol, nil]
      # @param new_scope_id [String, nil]
      # @param new_max_line [Integer, nil]
      # @param new_file_path [String, nil]
      # @return [ChainContext, nil]
      def child(new_scope_type: nil, new_scope_id: nil, new_max_line: nil, new_file_path: nil)
        return nil if @depth >= MAX_DEPTH # Depth limit reached

        ChainContext.new(
          chain_index: @chain_index,
          rbs_provider: @rbs_provider,
          type_matcher: @type_matcher,
          user_method_resolver: @user_method_resolver,
          scope_type: new_scope_type || @scope_type,
          scope_id: new_scope_id || @scope_id,
          file_path: new_file_path || @file_path,
          max_line: new_max_line || @max_line,
          depth: @depth + 1
        )
      end

      # Check if depth limit exceeded
      # @return [Boolean]
      def depth_exceeded?
        @depth >= MAX_DEPTH
      end

      # Lookup chain for a variable
      # @param var_name [String]
      # @return [Chain, nil]
      def lookup_chain(var_name)
        @chain_index.find_chain_at_location(
          var_name: var_name,
          scope_type: @scope_type,
          scope_id: @scope_id,
          max_line: @max_line,
          file_path: @file_path
        )
      end

      # Get method return type from RBS
      # @param class_name [String]
      # @param method_name [String]
      # @return [Types::Type]
      def get_method_return_type(class_name, method_name)
        @rbs_provider.get_method_return_type(class_name, method_name)
      end

      # Get method return type from user-defined methods
      # @param class_name [String]
      # @param method_name [String]
      # @return [Types::Type]
      def get_user_method_return_type(class_name, method_name)
        return Types::Unknown.instance unless @user_method_resolver

        @user_method_resolver.get_return_type(class_name, method_name)
      end

      # Get method return chains from ChainIndex
      # @param class_name [String]
      # @param method_name [String]
      # @return [Array<Chain>]
      def get_method_return_chains(class_name, method_name)
        @chain_index.get_method_return_chains(class_name, method_name)
      end

      # Heuristic type matching from method calls
      # @param method_calls [Array<String>]
      # @return [Array<Types::Type>]
      def find_matching_types(method_calls)
        return [] unless @type_matcher

        @type_matcher.find_matching_types(method_calls)
      end

      # Get method calls for a variable definition (for heuristic inference)
      # @param var_name [String]
      # @param def_line [Integer]
      # @param def_column [Integer]
      # @return [Array<Hash>]
      def get_method_calls(var_name:, def_line:, def_column:)
        return [] unless @file_path

        @chain_index.get_method_calls(
          file_path: @file_path,
          scope_type: @scope_type,
          scope_id: @scope_id,
          var_name: var_name,
          def_line: def_line,
          def_column: def_column
        )
      end

      # Find all definitions for a variable
      # @param var_name [String]
      # @return [Array<Hash>]
      def find_definitions(var_name)
        @chain_index.find_definitions(
          var_name: var_name,
          file_path: @file_path,
          scope_type: @scope_type,
          scope_id: @scope_id
        )
      end
    end
  end
end
