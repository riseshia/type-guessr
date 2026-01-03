# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents a .new call (constructor)
      # Example: User.new → User instance
      class NewCall < Link
        attr_reader :class_name, :arguments

        def initialize(class_name, arguments: [])
          super("new")
          @class_name = class_name
          @arguments = arguments.freeze  # Array of Chain for arguments
        end

        # .new always returns an instance of the class
        def resolve(_context, _receiver_type, _is_head)
          Types::ClassInstance.new(@class_name)
        end

        def ==(other)
          super && @class_name == other.class_name && @arguments == other.arguments
        end

        def hash
          [self.class, @class_name, @arguments].hash
        end

        def to_s
          "#{@class_name}.new"
        end
      end
    end
  end
end
