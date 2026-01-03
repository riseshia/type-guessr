# frozen_string_literal: true

module TypeGuessr
  module Core
    class Chain
      # Base class for all chain link components
      # Each link represents a step in resolving an expression
      class Link
        attr_reader :word

        def initialize(word = "<undefined>")
          @word = word
        end

        # Resolve this link in context
        # @param context [ChainContext] resolution context
        # @param receiver_type [Types::Type, nil] type from previous link (nil for head)
        # @param is_head [Boolean] true if this is the first link in chain
        # @return [Types::Type] resolved type
        def resolve(context, receiver_type, is_head)
          Types::Unknown.instance
        end

        def defined?
          @word != "<undefined>"
        end

        def to_s
          @word.to_s
        end

        def ==(other)
          self.class == other.class && @word == other.word
        end
        alias eql? ==

        def hash
          [self.class, @word].hash
        end
      end
    end
  end
end
