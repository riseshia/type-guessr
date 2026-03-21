# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Literal and type inference helpers for PrismConverter
      class PrismConverter
        private def convert_literal(prism_node)
          type = literal_type_for(prism_node)
          literal_value = extract_literal_value(prism_node)
          IR::LiteralNode.new(type, literal_value, nil, [], convert_loc(prism_node.location))
        end

        # Extract the actual value from a literal node (for Symbol, Integer, String)
        private def extract_literal_value(prism_node)
          case prism_node
          when Prism::SymbolNode
            prism_node.value.to_sym
          when Prism::IntegerNode
            prism_node.value
          when Prism::StringNode
            prism_node.content
          end
        end

        private def convert_array_literal(prism_node, context)
          type = array_element_type_for(prism_node)

          # Convert each element to an IR node
          value_nodes = prism_node.elements.filter_map do |elem|
            next if elem.nil?

            case elem
            when Prism::SplatNode
              # *arr → convert to CallNode for to_a
              splat_expr = convert(elem.expression, context)
              IR::CallNode.new(:to_a, splat_expr, [], [], nil, false, [], convert_loc(elem.location))
            else
              convert(elem, context)
            end
          end

          IR::LiteralNode.new(type, nil, value_nodes.empty? ? nil : value_nodes, [], convert_loc(prism_node.location))
        end

        private def convert_hash_literal(prism_node, context)
          type = hash_element_types_for(prism_node)
          build_hash_literal_node(prism_node, type, context)
        end

        # Convert KeywordHashNode (keyword arguments in method calls like `foo(a: 1, b: x)`)
        private def convert_keyword_hash(prism_node, context)
          type = infer_keyword_hash_type(prism_node)
          build_hash_literal_node(prism_node, type, context)
        end

        # Shared helper for hash-like nodes (HashNode, KeywordHashNode)
        private def build_hash_literal_node(prism_node, type, context)
          value_nodes = prism_node.elements.filter_map do |elem|
            case elem
            when Prism::AssocNode
              convert(elem.value, context)
            when Prism::AssocSplatNode
              convert(elem.value, context)
            end
          end

          IR::LiteralNode.new(type, nil, value_nodes.empty? ? nil : value_nodes, [], convert_loc(prism_node.location))
        end

        # Infer type for KeywordHashNode (always has symbol keys)
        private def infer_keyword_hash_type(keyword_hash_node)
          return Types::HashShape.new({}) if keyword_hash_node.elements.empty?

          fields = keyword_hash_node.elements.each_with_object({}) do |elem, hash|
            next unless elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)

            hash[elem.key.value.to_sym] = literal_type_for(elem.value)
          end
          Types::HashShape.new(fields)
        end

        private def literal_type_for(prism_node)
          case prism_node
          when Prism::IntegerNode
            Types::ClassInstance.for("Integer")
          when Prism::FloatNode
            Types::ClassInstance.for("Float")
          when Prism::StringNode, Prism::InterpolatedStringNode
            Types::ClassInstance.for("String")
          when Prism::SymbolNode
            Types::ClassInstance.for("Symbol")
          when Prism::TrueNode
            Types::ClassInstance.for("TrueClass")
          when Prism::FalseNode
            Types::ClassInstance.for("FalseClass")
          when Prism::NilNode
            Types::ClassInstance.for("NilClass")
          when Prism::ArrayNode
            # Infer element type from array contents
            array_element_type_for(prism_node)
          when Prism::HashNode
            hash_element_types_for(prism_node)
          when Prism::RangeNode
            range_element_type_for(prism_node)
          when Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode
            Types::ClassInstance.for("Regexp")
          when Prism::ImaginaryNode
            Types::ClassInstance.for("Complex")
          when Prism::RationalNode
            Types::ClassInstance.for("Rational")
          when Prism::XStringNode, Prism::InterpolatedXStringNode
            Types::ClassInstance.for("String")
          else
            Types::Unknown.instance
          end
        end

        private def range_element_type_for(range_node)
          left_type = range_node.left ? literal_type_for(range_node.left) : nil
          right_type = range_node.right ? literal_type_for(range_node.right) : nil

          types = [left_type, right_type].compact

          # No bounds at all (shouldn't happen in valid Ruby, but handle gracefully)
          return Types::RangeType.new if types.empty?

          unique_types = types.uniq

          element_type = if unique_types.size == 1
                           unique_types.first
                         else
                           Types::Union.new(unique_types)
                         end

          Types::RangeType.new(element_type)
        end

        private def array_element_type_for(array_node)
          return Types::TupleType.new([]) if array_node.elements.empty?

          element_types = array_node.elements.filter_map do |elem|
            literal_type_for(elem) unless elem.nil?
          end

          return Types::ArrayType.new if element_types.empty?

          if element_types.any?(Types::Unknown)
            # Splat or unknown elements → widen to ArrayType(Union)
            unique_types = element_types.uniq
            Types::ArrayType.new(Types::Union.new(unique_types))
          else
            Types::TupleType.new(element_types)
          end
        end

        private def hash_element_types_for(hash_node)
          return Types::HashShape.new({}) if hash_node.elements.empty?

          # Check if all keys are symbols for HashShape
          all_symbol_keys = hash_node.elements.all? do |elem|
            elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)
          end

          if all_symbol_keys
            # Build HashShape with field types
            fields = {}
            hash_node.elements.each do |elem|
              next unless elem.is_a?(Prism::AssocNode) && elem.key.is_a?(Prism::SymbolNode)

              field_name = elem.key.value.to_sym
              field_type = literal_type_for(elem.value)
              fields[field_name] = field_type
            end
            Types::HashShape.new(fields)
          else
            # Non-symbol keys or mixed keys - return HashType
            key_types = []
            value_types = []

            hash_node.elements.each do |elem|
              case elem
              when Prism::AssocNode
                key_types << literal_type_for(elem.key) if elem.key
                value_types << literal_type_for(elem.value) if elem.value
              end
            end

            return Types::HashType.new if key_types.empty? && value_types.empty?

            # Deduplicate types
            unique_key_types = key_types.uniq
            unique_value_types = value_types.uniq

            key_type = if unique_key_types.size == 1
                         unique_key_types.first
                       elsif unique_key_types.empty?
                         Types::Unknown.instance
                       else
                         Types::Union.new(unique_key_types)
                       end

            value_type = if unique_value_types.size == 1
                           unique_value_types.first
                         elsif unique_value_types.empty?
                           Types::Unknown.instance
                         else
                           Types::Union.new(unique_value_types)
                         end

            Types::HashType.new(key_type, value_type)
          end
        end
      end
    end
  end
end
