# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents an if/else expression
      # Examples: if condition then a else b end, condition ? a : b
      class If < Link
        attr_reader :condition, :then_chain, :else_chain

        def initialize(condition:, then_chain:, else_chain: nil)
          super("if")
          @condition = condition  # Chain for condition (not used for type inference)
          @then_chain = then_chain
          @else_chain = else_chain
        end

        # Resolve both branches and return union type
        def resolve(context, _receiver_type, _is_head)
          then_type = @then_chain&.resolve(context) || Types::ClassInstance.new("NilClass")
          else_type = @else_chain&.resolve(context) || Types::ClassInstance.new("NilClass")

          # If both types are the same, return single type
          return then_type if then_type == else_type

          # Otherwise return union
          Types::Union.new([then_type, else_type])
        end

        def ==(other)
          self.class == other.class &&
            @condition == other.condition &&
            @then_chain == other.then_chain &&
            @else_chain == other.else_chain
        end

        def hash
          [self.class, @condition, @then_chain, @else_chain].hash
        end

        def to_s
          "if"
        end
      end
    end
  end
end
