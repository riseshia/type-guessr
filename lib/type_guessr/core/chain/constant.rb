# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents a constant reference (class/module name)
      # Examples: User, String, ActiveRecord::Base
      class Constant < Link
        # Constants resolve to the class itself (not an instance)
        # This is used for chaining like: User.new, User.find
        def resolve(_context, _receiver_type, _is_head)
          # Return a ClassInstance representing the class itself
          # Note: This is a meta-type, not an instance
          Types::ClassInstance.new(@word)
        end
      end
    end
  end
end
