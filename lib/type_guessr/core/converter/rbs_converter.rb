# frozen_string_literal: true

require "rbs"
require_relative "../types"

module TypeGuessr
  module Core
    module Converter
      # Converts RBS types to internal type system
      # Isolates RBS type dependencies from the core type inference logic
      class RBSConverter
        # Convert RBS type to internal type system
        # @param rbs_type [RBS::Types::t] the RBS type
        # @param substitutions [Hash{Symbol => Types::Type}] type variable substitutions
        # @return [Types::Type] internal type representation
        def convert(rbs_type, substitutions = {})
          case rbs_type
          when RBS::Types::Variable
            convert_type_variable(rbs_type, substitutions)
          when RBS::Types::ClassInstance
            convert_class_instance(rbs_type, substitutions)
          when RBS::Types::Union
            convert_union(rbs_type, substitutions)
          when RBS::Types::Tuple
            convert_tuple(rbs_type, substitutions)
          when RBS::Types::Bases::Self, RBS::Types::Bases::Instance
            # Cannot resolve without context - return Unknown
            Types::Unknown.instance
          else
            # Unknown RBS type - return Unknown
            Types::Unknown.instance
          end
        end

        private

        # Convert RBS type variable to internal type
        # @param rbs_type [RBS::Types::Variable] RBS type variable
        # @param substitutions [Hash] type variable substitutions
        # @return [Types::Type] substituted type or TypeVariable
        def convert_type_variable(rbs_type, substitutions)
          # Check if we have a substitution for this type variable
          substituted = substitutions[rbs_type.name]
          return substituted if substituted

          # No substitution available - return TypeVariable
          Types::TypeVariable.new(rbs_type.name)
        end

        # Convert RBS ClassInstance to internal type
        # @param rbs_type [RBS::Types::ClassInstance] RBS class instance
        # @param substitutions [Hash] type variable substitutions
        # @return [Types::Type] internal type
        def convert_class_instance(rbs_type, substitutions)
          class_name = rbs_type.name.to_s.delete_prefix("::")

          # Handle Array with type parameter
          if class_name == "Array" && rbs_type.args.size == 1
            element_type = convert(rbs_type.args.first, substitutions)
            return Types::ArrayType.new(element_type)
          end

          # For other generic types, return ClassInstance (ignore type args for now)
          # TODO: Add HashType with key/value types in the future
          Types::ClassInstance.new(class_name)
        end

        # Convert RBS Union to internal Union type
        # @param rbs_type [RBS::Types::Union] RBS union type
        # @param substitutions [Hash] type variable substitutions
        # @return [Types::Union] internal union type
        def convert_union(rbs_type, substitutions)
          types = rbs_type.types.map { |t| convert(t, substitutions) }
          Types::Union.new(types)
        end

        # Convert RBS Tuple to internal ArrayType
        # Tuples like [K, V] are converted to Array[K | V]
        # @param rbs_type [RBS::Types::Tuple] RBS tuple type
        # @param substitutions [Hash] type variable substitutions
        # @return [Types::ArrayType] internal array type with union element type
        def convert_tuple(rbs_type, substitutions)
          element_types = rbs_type.types.map { |t| convert(t, substitutions) }
          Types::ArrayType.new(Types::Union.new(element_types))
        end
      end
    end
  end
end
