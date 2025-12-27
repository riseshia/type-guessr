# frozen_string_literal: true

require "prism"
require_relative "types"

module TypeGuessr
  module Core
    # Analyzes literal nodes and infers their types
    # Centralizes literal type inference logic used across the codebase
    class LiteralTypeAnalyzer
      # Infer type from a Prism literal node
      # @param node [Prism::Node] the node to analyze
      # @return [Types::Type, nil] the inferred type or nil if cannot be determined
      def self.infer(node)
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
          Types::ArrayType.new
        when Prism::HashNode
          Types::ClassInstance.new("Hash")
        when Prism::RangeNode
          Types::ClassInstance.new("Range")
        when Prism::RegularExpressionNode
          Types::ClassInstance.new("Regexp")
        end
      end
    end
  end
end
