# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents an or/and expression
      # Examples: a || b, a && b
      class Or < Link
        attr_reader :left_chain, :right_chain

        def initialize(left_chain:, right_chain:, operator: "||")
          super(operator)
          @left_chain = left_chain
          @right_chain = right_chain
        end

        # Resolve both sides and return union type
        def resolve(context, _receiver_type, _is_head)
          left_type = @left_chain&.resolve(context) || Types::Unknown.instance
          right_type = @right_chain&.resolve(context) || Types::Unknown.instance

          # If both types are the same, return single type
          return left_type if left_type == right_type

          # Otherwise return union
          Types::Union.new([left_type, right_type])
        end

        def ==(other)
          self.class == other.class &&
            @word == other.word &&
            @left_chain == other.left_chain &&
            @right_chain == other.right_chain
        end

        def hash
          [self.class, @word, @left_chain, @right_chain].hash
        end

        def to_s
          @word
        end
      end
    end
  end
end
