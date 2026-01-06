# frozen_string_literal: true

require "singleton"

module TypeGuessr
  module Core
    module Types
      # Base class for all type representations
      class Type
        def ==(other)
          eql?(other)
        end

        def eql?(other)
          self.class == other.class
        end

        def hash
          self.class.hash
        end

        # Substitute type variables with concrete types
        # @param substitutions [Hash{Symbol => Type}] type variable substitutions
        # @return [Type] the type with substitutions applied (self if no change)
        def substitute(_substitutions)
          self
        end
      end

      # Unknown type - no information available
      class Unknown < Type
        include Singleton

        def to_s
          "untyped"
        end
      end

      # ClassInstance - instance of a class
      class ClassInstance < Type
        attr_reader :name

        def initialize(name)
          super()
          @name = name
        end

        def eql?(other)
          super && @name == other.name
        end

        def hash
          [self.class, @name].hash
        end

        def to_s
          case @name
          when "NilClass" then "nil"
          when "TrueClass" then "true"
          when "FalseClass" then "false"
          else @name
          end
        end
      end

      # Union - union of multiple types
      class Union < Type
        attr_reader :types

        DEFAULT_CUTOFF = 10

        def initialize(types, cutoff: DEFAULT_CUTOFF)
          super()
          @types = normalize(types, cutoff)
        end

        def eql?(other)
          return false unless super

          # Compare as sets since order doesn't matter
          @types.to_set == other.types.to_set
        end

        def hash
          [self.class, @types.to_set].hash
        end

        def to_s
          # Handle optional type: exactly 2 types where one is NilClass → ?Type
          if optional_type?
            "?#{non_nil_type}"
          else
            @types.map(&:to_s).join(" | ")
          end
        end

        def substitute(substitutions)
          new_types = @types.map { |t| t.substitute(substitutions) }
          return self if new_types.zip(@types).all? { |new_t, old_t| new_t.equal?(old_t) }

          Union.new(new_types)
        end

        private

        def optional_type?
          @types.size == 2 && @types.any? { |t| nil_type?(t) }
        end

        def nil_type?(type)
          type.is_a?(ClassInstance) && type.name == "NilClass"
        end

        def non_nil_type
          @types.find { |t| !nil_type?(t) }
        end

        def normalize(types, cutoff)
          # Flatten nested unions
          flattened = flatten_unions(types)

          # Deduplicate
          deduplicated = flattened.uniq

          # Remove Unknown if other types are present
          filtered = remove_unknown_if_others_present(deduplicated)

          # Apply cutoff
          apply_cutoff(filtered, cutoff)
        end

        def flatten_unions(types)
          types.flat_map do |type|
            type.is_a?(Union) ? type.types : type
          end
        end

        def remove_unknown_if_others_present(types)
          return types if types.size <= 1

          non_unknown = types.reject { |t| t.is_a?(Unknown) }
          non_unknown.empty? ? types : non_unknown
        end

        def apply_cutoff(types, cutoff)
          types.take(cutoff)
        end
      end

      # ArrayType - array with element type
      class ArrayType < Type
        attr_reader :element_type

        def initialize(element_type = Unknown.instance)
          super()
          @element_type = element_type
        end

        def eql?(other)
          super && @element_type == other.element_type
        end

        def hash
          [self.class, @element_type].hash
        end

        def to_s
          "Array[#{@element_type}]"
        end

        def substitute(substitutions)
          new_element = @element_type.substitute(substitutions)
          return self if new_element.equal?(@element_type)

          ArrayType.new(new_element)
        end
      end

      # HashType - hash with key and value types
      class HashType < Type
        attr_reader :key_type, :value_type

        def initialize(key_type = Unknown.instance, value_type = Unknown.instance)
          super()
          @key_type = key_type
          @value_type = value_type
        end

        def eql?(other)
          super && @key_type == other.key_type && @value_type == other.value_type
        end

        def hash
          [self.class, @key_type, @value_type].hash
        end

        def to_s
          "Hash[#{@key_type}, #{@value_type}]"
        end

        def substitute(substitutions)
          new_key = @key_type.substitute(substitutions)
          new_value = @value_type.substitute(substitutions)
          return self if new_key.equal?(@key_type) && new_value.equal?(@value_type)

          HashType.new(new_key, new_value)
        end
      end

      # HashShape - hash with known field types (Symbol/String keys only)
      class HashShape < Type
        attr_reader :fields

        DEFAULT_MAX_FIELDS = 15

        def self.new(fields, max_fields: DEFAULT_MAX_FIELDS)
          # Widen to generic Hash when too many fields
          return ClassInstance.new("Hash") if fields.size > max_fields

          super(fields)
        end

        def initialize(fields)
          super()
          @fields = fields
        end

        def eql?(other)
          super && @fields == other.fields
        end

        def hash
          [self.class, @fields].hash
        end

        def to_s
          return "{ }" if @fields.empty?

          fields_str = @fields.map { |k, v| "#{k}: #{v}" }.join(", ")
          "{ #{fields_str} }"
        end

        def merge_field(key, value_type, max_fields: DEFAULT_MAX_FIELDS)
          new_fields = @fields.merge(key => value_type)
          HashShape.new(new_fields, max_fields: max_fields)
        end

        def substitute(substitutions)
          new_fields = @fields.transform_values { |v| v.substitute(substitutions) }
          return self if new_fields.all? { |k, v| v.equal?(@fields[k]) }

          HashShape.new(new_fields)
        end
      end

      # TypeVariable - represents a type variable from RBS (e.g., Elem, K, V, U)
      class TypeVariable < Type
        attr_reader :name

        def initialize(name)
          super()
          @name = name
        end

        def eql?(other)
          super && @name == other.name
        end

        def hash
          [self.class, @name].hash
        end

        def to_s
          @name.to_s
        end

        def substitute(substitutions)
          substitutions[@name] || self
        end
      end

      # DuckType - represents a type inferred from method calls (duck typing)
      class DuckType < Type
        attr_reader :methods

        def initialize(methods)
          super()
          @methods = methods.sort
        end

        def eql?(other)
          super && @methods == other.methods
        end

        def hash
          [self.class, @methods].hash
        end

        def to_s
          methods_str = @methods.map { |m| "##{m}" }.join(", ")
          "(responds to #{methods_str})"
        end
      end

      # ForwardingArgs - represents the forwarding parameter (...)
      class ForwardingArgs < Type
        include Singleton

        def to_s
          "..."
        end
      end
    end
  end
end
