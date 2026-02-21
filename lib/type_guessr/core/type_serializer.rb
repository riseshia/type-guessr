# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # Converts Type objects to/from JSON-compatible Hashes.
    # Used by GemSignatureCache for persisting inferred method signatures.
    module TypeSerializer
      module_function def serialize(type)
        case type
        when Types::Unknown
          { "_type" => "Unknown" }
        when Types::ClassInstance
          { "_type" => "ClassInstance", "name" => type.name }
        when Types::SingletonType
          { "_type" => "SingletonType", "name" => type.name }
        when Types::TupleType
          { "_type" => "TupleType", "element_types" => type.element_types.map { |t| serialize(t) } }
        when Types::ArrayType
          { "_type" => "ArrayType", "element_type" => serialize(type.element_type) }
        when Types::HashShape
          { "_type" => "HashShape", "fields" => type.fields.transform_keys(&:to_s).transform_values { |v| serialize(v) } }
        when Types::HashType
          { "_type" => "HashType", "key_type" => serialize(type.key_type), "value_type" => serialize(type.value_type) }
        when Types::RangeType
          { "_type" => "RangeType", "element_type" => serialize(type.element_type) }
        when Types::Union
          { "_type" => "Union", "types" => type.types.map { |t| serialize(t) } }
        when Types::TypeVariable
          { "_type" => "TypeVariable", "name" => type.name.to_s }
        when Types::SelfType
          { "_type" => "SelfType" }
        when Types::ForwardingArgs
          { "_type" => "ForwardingArgs" }
        when Types::MethodSignature
          { "_type" => "MethodSignature",
            "return_type" => serialize(type.return_type),
            "params" => type.params.map { |p| serialize_param(p) } }
        end
      end

      # Deserialize a Hash back to a Type object
      # @param hash [Hash] JSON-compatible hash with "_type" discriminator
      # @return [Types::Type] The deserialized type
      # @raise [ArgumentError] if "_type" is unknown
      module_function def deserialize(hash)
        case hash["_type"]
        when "Unknown"          then Types::Unknown.instance
        when "ClassInstance"    then Types::ClassInstance.for(hash["name"])
        when "SingletonType"    then Types::SingletonType.new(hash["name"])
        when "ArrayType"        then Types::ArrayType.new(deserialize(hash["element_type"]))
        when "TupleType"        then Types::TupleType.new(hash["element_types"].map { |t| deserialize(t) })
        when "HashType"         then Types::HashType.new(deserialize(hash["key_type"]), deserialize(hash["value_type"]))
        when "RangeType"        then Types::RangeType.new(deserialize(hash["element_type"]))
        when "HashShape"        then Types::HashShape.new(hash["fields"].to_h { |k, v| [k.to_sym, deserialize(v)] })
        when "Union"            then Types::Union.new(hash["types"].map { |t| deserialize(t) })
        when "TypeVariable"     then Types::TypeVariable.new(hash["name"].to_sym)
        when "SelfType"         then Types::SelfType.instance
        when "ForwardingArgs"   then Types::ForwardingArgs.instance
        when "MethodSignature"  then deserialize_method_signature(hash)
        else
          raise ArgumentError, "Unknown type: #{hash["_type"]}"
        end
      end

      # @param param [Types::ParamSignature]
      # @return [Hash]
      module_function def serialize_param(param)
        { "name" => param.name.to_s, "kind" => param.kind.to_s, "type" => serialize(param.type) }
      end

      # @param hash [Hash]
      # @return [Types::MethodSignature]
      module_function def deserialize_method_signature(hash)
        params = hash["params"].map do |p|
          Types::ParamSignature.new(
            name: p["name"].to_sym,
            kind: p["kind"].to_sym,
            type: deserialize(p["type"])
          )
        end
        Types::MethodSignature.new(params, deserialize(hash["return_type"]))
      end

      private_class_method :serialize_param, :deserialize_method_signature
    end
  end
end
