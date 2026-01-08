# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # Simplifies types by unwrapping single-element unions and
    # unifying parent/child class relationships
    class TypeSimplifier
      # @param ancestry_provider [Proc, nil] A proc that takes class_name and returns array of ancestor names
      def initialize(ancestry_provider: nil)
        @ancestry_provider = ancestry_provider
      end

      # Simplify a type
      # @param type [Types::Type] The type to simplify
      # @return [Types::Type] The simplified type
      def simplify(type)
        case type
        when Types::Union
          simplify_union(type)
        else
          type
        end
      end

      private

      def simplify_union(union)
        types = union.types

        # 1. Single element: unwrap
        return types.first if types.size == 1

        # 2. Filter to most general types (remove children when parent is present)
        types = filter_to_most_general_types(types) if @ancestry_provider

        # 3. Check again after filtering
        return types.first if types.size == 1

        # 4. Multiple elements remain: create new Union
        Types::Union.new(types)
      end

      # Filter out types whose ancestor is also in the list
      # @param types [Array<Types::Type>] List of types
      # @return [Array<Types::Type>] Filtered list with only the most general types
      def filter_to_most_general_types(types)
        # Extract class names from ClassInstance types
        class_names = types.filter_map do |t|
          t.name if t.is_a?(Types::ClassInstance)
        end

        types.reject do |type|
          next false unless type.is_a?(Types::ClassInstance)

          ancestors = @ancestry_provider.call(type.name)
          # Check if any ancestor (excluding self) is also in the list
          ancestors.any? { |ancestor| ancestor != type.name && class_names.include?(ancestor) }
        end
      end
    end
  end
end
