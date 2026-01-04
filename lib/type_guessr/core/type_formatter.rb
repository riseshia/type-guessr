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
          # Format each type and join with pipe
          type.types.map { |t| format(t) }.join(" | ")
        when Types::ArrayType
          "Array[#{format(type.element_type)}]"
        when Types::HashShape
          format_hash_shape(type)
        when Types::TypeVariable
          type.name.to_s
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

      private_class_method :format_hash_shape
    end
  end
end
