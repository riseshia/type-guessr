# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents a literal value (string, integer, array, etc.)
      # Examples: "hello", 42, [1, 2, 3], { name: "John" }
      class Literal < Link
        attr_reader :type

        def initialize(type)
          super(type.to_s)
          @type = type
        end

        # Literals always resolve to their stored type
        def resolve(_context, _receiver_type, _is_head)
          @type
        end

        def ==(other)
          super && @type == other.type
        end

        def hash
          [self.class, @type].hash
        end
      end
    end
  end
end
