# frozen_string_literal: true

require "prism"
require_relative "types"

module TypeGuessr
  module Core
    # Analyzes literal nodes and infers their types
    # Centralizes literal type inference logic used across the codebase
    class LiteralTypeAnalyzer
      # Maximum number of array elements to sample for type inference
      MAX_ARRAY_SAMPLES = 5

      # Maximum number of unique element types before falling back to untyped
      # Arrays with 1-3 unique types get specific typing, 4+ get untyped
      MAX_ELEMENT_TYPES = 3

      # Maximum nesting depth for array type inference
      # Prevents infinite recursion and keeps types readable
      MAX_NESTING_DEPTH = 1

      # Infer type from a Prism literal node
      # @param node [Prism::Node] the node to analyze
      # @param depth [Integer] current nesting depth for arrays (internal)
      # @return [Types::Type, nil] the inferred type or nil if cannot be determined
      def self.infer(node, depth: 0)
        case node
        when Prism::IntegerNode
          Types::ClassInstance.new("Integer")
        when Prism::FloatNode
          Types::ClassInstance.new("Float")
        when Prism::StringNode, Prism::InterpolatedStringNode
          Types::ClassInstance.new("String")
        when Prism::SymbolNode
          Types::ClassInstance.new("Symbol")
        when Prism::TrueNode
          Types::ClassInstance.new("TrueClass")
        when Prism::FalseNode
          Types::ClassInstance.new("FalseClass")
        when Prism::NilNode
          Types::ClassInstance.new("NilClass")
        when Prism::ArrayNode
          # Rule 5: Stop recursion at max nesting depth
          # Return nil so it gets filtered out by compact, leading to Unknown element type
          return nil if depth > MAX_NESTING_DEPTH

          infer_array_type(node, depth)
        when Prism::HashNode
          infer_hash_type(node, depth)
        when Prism::RangeNode
          Types::ClassInstance.new("Range")
        when Prism::RegularExpressionNode
          Types::ClassInstance.new("Regexp")
        end
      end

      # Infer element type for array literals
      # @param node [Prism::ArrayNode] the array node
      # @param depth [Integer] current nesting depth
      # @return [Types::ArrayType] array type with inferred element type
      def self.infer_array_type(node, depth)
        # Rule 4: Empty arrays → Array[untyped]
        return Types::ArrayType.new if node.elements.empty?

        # Rule 7: Sample only first MAX_ARRAY_SAMPLES elements
        samples = node.elements.take(MAX_ARRAY_SAMPLES)

        # Infer type for each sampled element
        element_types = samples.map do |element|
          # Only increment depth for nested arrays
          next_depth = element.is_a?(Prism::ArrayNode) ? depth + 1 : depth
          infer(element, depth: next_depth)
        end.compact # Remove nils (non-literal elements)

        # Rule 6: If we couldn't infer any types (all non-literals) → untyped
        return Types::ArrayType.new if element_types.empty?

        # Get unique types
        unique_types = element_types.uniq

        # Rule 1: Homogeneous (1 unique type) → typed array
        return Types::ArrayType.new(unique_types.first) if unique_types.size == 1

        # Rule 3: Too many types (4+) → Array[untyped]
        return Types::ArrayType.new if unique_types.size > MAX_ELEMENT_TYPES

        # Rule 2: Mixed types (2-3) → Array[Union]
        Types::ArrayType.new(Types::Union.new(unique_types))
      end

      private_class_method :infer_array_type

      # Infer type for hash literals
      # @param node [Prism::HashNode] the hash node
      # @param depth [Integer] current nesting depth
      # @return [Types::Type] hash type (HashShape for symbol keys, Hash otherwise)
      def self.infer_hash_type(node, depth)
        # Empty hash → generic Hash
        return Types::ClassInstance.new("Hash") if node.elements.empty?

        # Check if all keys are symbols (for HashShape)
        fields = {}

        node.elements.each do |element|
          # Only handle AssocNode (key-value pairs)
          next unless element.is_a?(Prism::AssocNode)

          key = element.key
          value = element.value

          # Only symbol keys qualify for HashShape
          unless key.is_a?(Prism::SymbolNode)
            # Non-symbol key → fall back to generic Hash
            return Types::ClassInstance.new("Hash")
          end

          key_name = key.value.to_sym
          value_type = infer(value, depth: depth) || Types::Unknown.instance
          fields[key_name] = value_type
        end

        # HashShape.new will fall back to Hash if too many fields
        Types::HashShape.new(fields)
      end

      private_class_method :infer_hash_type
    end
  end
end
