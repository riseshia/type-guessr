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

        # Get the RBS class name for this type
        # Used for looking up method signatures in RBSProvider
        # @return [String, nil] class name or nil if not applicable
        def rbs_class_name
          nil
        end

        # Get type variable substitutions for this type
        # Used for substituting type variables in block parameters
        # @return [Hash{Symbol => Type}] type variable substitutions (e.g., { Elem: Integer, K: Symbol, V: String })
        def type_variable_substitutions
          {}
        end

        # Readable inspect output for debugging
        # @return [String]
        def inspect
          "#<#{self.class.name.split("::").last}>"
        end
      end

      # Unknown type - no information available
      class Unknown < Type
        include Singleton

        def to_s
          "untyped"
        end
      end

      # Unguessed type - type exists but has not been inferred yet
      # Used for lazy gem inference: method signatures are cached with
      # Unguessed return/param types until background inference completes.
      class Unguessed < Type
        include Singleton

        def to_s
          "unguessed"
        end
      end

      # ClassInstance - instance of a class
      class ClassInstance < Type
        CACHE = {} # rubocop:disable Style/MutableConstant

        # Factory method that caches instances for reuse
        # @param name [String] The class name
        # @return [ClassInstance] Cached or new instance
        def self.for(name)
          CACHE[name] ||= new(name).freeze
        end

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

        def inspect
          "#<ClassInstance:#{@name}>"
        end

        def rbs_class_name
          @name
        end
      end

      # SingletonType - represents the class object itself (singleton class)
      class SingletonType < Type
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
          "singleton(#{@name})"
        end

        def inspect
          "#<SingletonType:#{@name}>"
        end

        def rbs_class_name
          @name
        end
      end

      # Union - union of multiple types
      class Union < Type
        attr_reader :types

        def initialize(types, cutoff: 10)
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
          if bool_type?
            "bool"
          elsif optional_type?
            "?#{non_nil_type}"
          else
            @types.map(&:to_s).sort.join(" | ")
          end
        end

        def inspect
          "#<Union:#{@types.map(&:to_s).join("|")}>"
        end

        def substitute(substitutions)
          new_types = @types.map { |t| t.substitute(substitutions) }
          return self if new_types.zip(@types).all? { |new_t, old_t| new_t.equal?(old_t) }

          Union.new(new_types)
        end

        private def bool_type?
          return false unless @types.size == 2

          has_true = @types.any? { |t| t.is_a?(ClassInstance) && t.name == "TrueClass" }
          has_false = @types.any? { |t| t.is_a?(ClassInstance) && t.name == "FalseClass" }
          has_true && has_false
        end

        private def optional_type?
          @types.size == 2 && @types.any? { |t| nil_type?(t) }
        end

        private def nil_type?(type)
          type.is_a?(ClassInstance) && type.name == "NilClass"
        end

        private def non_nil_type
          @types.find { |t| !nil_type?(t) }
        end

        private def normalize(types, cutoff)
          # Flatten nested unions
          flattened = flatten_unions(types)

          # Deduplicate
          deduplicated = flattened.uniq

          # Simplify to Unknown if Unknown is present (T | untyped = untyped)
          filtered = simplify_if_unknown_present(deduplicated)

          # Apply cutoff
          apply_cutoff(filtered, cutoff)
        end

        private def flatten_unions(types)
          types.flat_map do |type|
            type.is_a?(Union) ? type.types : type
          end
        end

        private def simplify_if_unknown_present(types)
          return types if types.size <= 1

          has_unknown = types.any? { |t| t.is_a?(Unknown) }
          has_unknown ? [Unknown.instance] : types
        end

        private def apply_cutoff(types, cutoff)
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

        def inspect
          "#<ArrayType:#{@element_type}>"
        end

        def substitute(substitutions)
          new_element = @element_type.substitute(substitutions)
          return self if new_element.equal?(@element_type)

          ArrayType.new(new_element)
        end

        def rbs_class_name
          "Array"
        end

        def type_variable_substitutions
          { Elem: @element_type }
        end
      end

      # TupleType - array with per-position element types
      # Preserves positional type information for mixed-type array literals
      # Falls back to ArrayType when element count exceeds MAX_ELEMENTS
      class TupleType < Type
        attr_reader :element_types

        MAX_ELEMENTS = 8

        def self.new(element_types)
          return ArrayType.new(Union.new(element_types)) if element_types.size > MAX_ELEMENTS

          super
        end

        def initialize(element_types)
          super()
          @element_types = element_types
        end

        def eql?(other)
          super && @element_types == other.element_types
        end

        def hash
          [self.class, @element_types].hash
        end

        def to_s
          "[#{@element_types.join(", ")}]"
        end

        def inspect
          "#<TupleType:#{self}>"
        end

        def substitute(substitutions)
          new_types = @element_types.map { |t| t.substitute(substitutions) }
          return self if new_types.zip(@element_types).all? { |n, o| n.equal?(o) }

          TupleType.new(new_types)
        end

        def rbs_class_name
          "Array"
        end

        def type_variable_substitutions
          unique = @element_types.uniq
          elem = unique.size == 1 ? unique.first : Union.new(unique)
          { Elem: elem }
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

        def inspect
          "#<HashType:#{@key_type},#{@value_type}>"
        end

        def substitute(substitutions)
          new_key = @key_type.substitute(substitutions)
          new_value = @value_type.substitute(substitutions)
          return self if new_key.equal?(@key_type) && new_value.equal?(@value_type)

          HashType.new(new_key, new_value)
        end

        def rbs_class_name
          "Hash"
        end

        def type_variable_substitutions
          { K: @key_type, V: @value_type }
        end
      end

      # RangeType - range with element type
      class RangeType < Type
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
          "Range[#{@element_type}]"
        end

        def inspect
          "#<RangeType:#{@element_type}>"
        end

        def substitute(substitutions)
          new_element = @element_type.substitute(substitutions)
          return self if new_element.equal?(@element_type)

          RangeType.new(new_element)
        end

        def rbs_class_name
          "Range"
        end

        def type_variable_substitutions
          { Elem: @element_type }
        end
      end

      # HashShape - hash with known field types (Symbol/String keys only)
      class HashShape < Type
        attr_reader :fields

        def self.new(fields, max_fields: 15)
          # Widen to generic Hash when too many fields
          return ClassInstance.for("Hash") if fields.size > max_fields

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

        def inspect
          "#<HashShape:#{self}>"
        end

        def merge_field(key, value_type, max_fields: 15)
          new_fields = @fields.merge(key => value_type)
          HashShape.new(new_fields, max_fields: max_fields)
        end

        def substitute(substitutions)
          new_fields = @fields.transform_values { |v| v.substitute(substitutions) }
          return self if new_fields.all? { |k, v| v.equal?(@fields[k]) }

          HashShape.new(new_fields)
        end

        def rbs_class_name
          "Hash"
        end

        def type_variable_substitutions
          key_type = ClassInstance.for("Symbol")
          value_types = @fields.values.uniq
          value_type = if value_types.empty?
                         Unknown.instance
                       elsif value_types.size == 1
                         value_types.first
                       else
                         Union.new(value_types)
                       end
          { K: key_type, V: value_type }
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

        def inspect
          "#<TypeVariable:#{@name}>"
        end

        def substitute(substitutions)
          substitutions[@name] || self
        end
      end

      # SelfType - represents the 'self' type from RBS
      # Gets substituted with the receiver type at resolution time
      class SelfType < Type
        include Singleton

        def to_s
          "self"
        end

        def substitute(substitutions)
          substitutions[:self] || self
        end
      end

      # ForwardingArgs - represents the forwarding parameter (...)
      class ForwardingArgs < Type
        include Singleton

        def to_s
          "..."
        end
      end

      # ParamSignature - structural component of MethodSignature (not a Type)
      # Represents a single parameter with its name, kind, and inferred type
      ParamSignature = Data.define(:name, :kind, :type) do
        def to_s
          type_str = type.to_s
          case kind
          when :required         then "#{type_str} #{name}"
          when :optional         then "?#{type_str} #{name}"
          when :rest             then "*#{type_str} #{name}"
          when :keyword_required then "#{name}: #{type_str}"
          when :keyword_optional then "#{name}: ?#{type_str}"
          when :keyword_rest     then "**#{type_str} #{name}"
          when :block            then "&#{type_str} #{name}"
          when :forwarding       then "..."
          end
        end
      end

      # MethodSignature - first-class type for Proc/Lambda/Method signatures
      # Follows the same pattern as ArrayType: holds inner types and delegates substitute
      class MethodSignature < Type
        attr_reader :params, :return_type

        def initialize(params, return_type)
          super()
          @params = params
          @return_type = return_type
        end

        def eql?(other)
          super && @params == other.params && @return_type == other.return_type
        end

        def hash
          [self.class, @params, @return_type].hash
        end

        def to_s
          params_str = @params.map(&:to_s).join(", ")
          "(#{params_str}) -> #{@return_type}"
        end

        def inspect
          "#<MethodSignature:#{self}>"
        end

        def substitute(substitutions)
          new_params = @params.map do |p|
            ParamSignature.new(name: p.name, kind: p.kind, type: p.type.substitute(substitutions))
          end
          new_return_type = @return_type.substitute(substitutions)
          return self if new_params == @params && new_return_type.equal?(@return_type)

          MethodSignature.new(new_params, new_return_type)
        end

        def rbs_class_name
          "Proc"
        end
      end
    end
  end
end
