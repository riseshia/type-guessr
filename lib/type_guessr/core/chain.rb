# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # Represents an expression as a sequence of Links
    # Stored during AST parse, resolved lazily at hover time
    class Chain
      attr_reader :links, :location

      def initialize(links, location: nil)
        @links = links.freeze
        @location = location
      end

      # Lazy evaluation - resolve type at hover time
      # @param context [ChainContext] resolution context
      # @return [Types::Type] resolved type
      def resolve(context)
        return Types::Unknown.instance if @links.empty?

        current_type = nil
        @links.each_with_index do |link, index|
          current_type = link.resolve(context, current_type, index.zero?)
          return Types::Unknown.instance if current_type == Types::Unknown.instance
        end

        current_type || Types::Unknown.instance
      end

      # Check if chain is fully defined (no unknown links)
      def defined?
        @links.all?(&:defined?)
      end

      # Human-readable representation
      def to_s
        @links.map(&:to_s).join(".")
      end

      def ==(other)
        other.is_a?(Chain) && @links == other.links
      end
      alias eql? ==

      def hash
        @links.hash
      end
    end
  end
end
