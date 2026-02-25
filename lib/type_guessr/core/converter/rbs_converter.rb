# frozen_string_literal: true

require "rbs"
require_relative "../types"

module TypeGuessr
  module Core
    module Converter
      # Converts RBS types to internal type system
      # Isolates RBS type dependencies from the core type inference logic
      #
      # This class only handles conversion (RBS → internal types).
      # Type variable substitution is handled separately by Type#substitute.
      class RBSConverter
        # Convert RBS type to internal type system
        # @param rbs_type [RBS::Types::t] the RBS type
        # @return [Types::Type] internal type representation (TypeVariables preserved)
        def convert(rbs_type)
          case rbs_type
          when RBS::Types::Variable
            Types::TypeVariable.new(rbs_type.name)
          when RBS::Types::ClassInstance
            convert_class_instance(rbs_type)
          when RBS::Types::ClassSingleton
            # Class singleton type (e.g., singleton(String))
            class_name = rbs_type.name.to_s.delete_prefix("::")
            Types::SingletonType.new(class_name)
          when RBS::Types::Union
            convert_union(rbs_type)
          when RBS::Types::Tuple
            convert_tuple(rbs_type)
          when RBS::Types::Bases::Bool
            # bool is a type alias for TrueClass | FalseClass
            Types::ClassInstance.for("bool")
          when RBS::Types::Bases::Void
            Types::ClassInstance.for("void")
          when RBS::Types::Bases::Nil
            Types::ClassInstance.for("NilClass")
          when RBS::Types::Bases::Self
            Types::SelfType.instance
          when RBS::Types::Bases::Instance
            # Cannot resolve without context - return Unknown
            Types::Unknown.instance
          else
            # Unknown RBS type - return Unknown
            Types::Unknown.instance
          end
        end

        private def convert_class_instance(rbs_type)
          class_name = rbs_type.name.to_s.delete_prefix("::")

          # Handle Array with type parameter
          if class_name == "Array" && rbs_type.args.size == 1
            element_type = convert(rbs_type.args.first)
            return Types::ArrayType.new(element_type)
          end

          # Handle Hash with key/value type parameters
          if class_name == "Hash" && rbs_type.args.size == 2
            key_type = convert(rbs_type.args[0])
            value_type = convert(rbs_type.args[1])
            return Types::HashType.new(key_type, value_type)
          end

          # Handle Range with element type parameter
          if class_name == "Range" && rbs_type.args.size == 1
            element_type = convert(rbs_type.args.first)
            return Types::RangeType.new(element_type)
          end

          # For other generic types, return ClassInstance (ignore type args for now)
          Types::ClassInstance.for(class_name)
        end

        # Convert RBS Union to internal Union type
        # @param rbs_type [RBS::Types::Union] RBS union type
        # @return [Types::Union] internal union type
        private def convert_union(rbs_type)
          types = rbs_type.types.map { |t| convert(t) }
          Types::Union.new(types)
        end

        # Convert RBS Tuple to internal ArrayType
        # Tuples like [K, V] are converted to Array[K | V]
        # @param rbs_type [RBS::Types::Tuple] RBS tuple type
        # @return [Types::ArrayType] internal array type with union element type
        private def convert_tuple(rbs_type)
          element_types = rbs_type.types.map { |t| convert(t) }
          Types::ArrayType.new(Types::Union.new(element_types))
        end
      end
    end
  end
end
