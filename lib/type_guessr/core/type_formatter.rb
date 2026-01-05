# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # TypeFormatter converts Type objects to RBS-style string representations
    class TypeFormatter
      # Format a type object to RBS-style string
      # @param type [Types::Type] the type to format
      # @return [String] RBS-style string representation
      def self.format(type)
        case type
        when Types::Unknown
          "untyped"
        when Types::ClassInstance
          format_class_instance(type)
        when Types::Union
          if optional_type?(type)
            "?#{format(non_nil_type(type))}"
          else
            type.types.map { |t| format(t) }.join(" | ")
          end
        when Types::ArrayType
          "Array[#{format(type.element_type)}]"
        when Types::HashType
          "Hash[#{format(type.key_type)}, #{format(type.value_type)}]"
        when Types::HashShape
          format_hash_shape(type)
        when Types::TypeVariable
          type.name.to_s
        when Types::DuckType
          format_duck_type(type)
        when Types::ForwardingArgs
          "..."
        else
          "untyped"
        end
      end

      # Format ClassInstance with special handling for singleton types
      # @param type [Types::ClassInstance] the class instance to format
      # @return [String] formatted type name
      def self.format_class_instance(type)
        case type.name
        when "NilClass"
          "nil"
        when "TrueClass"
          "true"
        when "FalseClass"
          "false"
        else
          type.name
        end
      end

      # Format HashShape with field types
      # @param hash_shape [Types::HashShape] the hash shape to format
      # @return [String] formatted hash shape
      def self.format_hash_shape(hash_shape)
        return "{ }" if hash_shape.fields.empty?

        fields_str = hash_shape.fields.map { |k, v| "#{k}: #{format(v)}" }.join(", ")
        "{ #{fields_str} }"
      end

      # Format DuckType showing methods it responds to
      # @param duck_type [Types::DuckType] the duck type to format
      # @return [String] formatted duck type
      def self.format_duck_type(duck_type)
        methods_str = duck_type.methods.map { |m| "##{m}" }.join(", ")
        "(responds to #{methods_str})"
      end

      # Check if union is an optional type (exactly one type + nil)
      def self.optional_type?(union)
        union.types.size == 2 && union.types.any? { |t| nil_type?(t) }
      end

      # Check if type is NilClass
      def self.nil_type?(type)
        type.is_a?(Types::ClassInstance) && type.name == "NilClass"
      end

      # Get the non-nil type from an optional union
      def self.non_nil_type(union)
        union.types.find { |t| !nil_type?(t) }
      end

      private_class_method :format_hash_shape, :format_duck_type,
                           :optional_type?, :nil_type?, :non_nil_type
    end
  end
end
