# frozen_string_literal: true

require "prism"

module TypeGuessr
  module Core
    # Visitor to find the innermost DefNode containing a target position
    # Used by FlowAnalyzer integration to locate the enclosing method definition
    class DefNodeFinder < Prism::Visitor
      attr_reader :result

      def initialize(target_line, target_column)
        super()
        @target_line = target_line
        @target_column = target_column
        @result = nil
      end

      def visit_def_node(node)
        # If this method contains the target position, it's a candidate
        return unless contains_position?(node)

        @result = node
        # Continue visiting children to find innermost method
        super
      end

      private

      def contains_position?(node)
        loc = node.location
        # Check if target position is within this node's range
        if @target_line > loc.start_line && @target_line < loc.end_line
          true
        elsif @target_line == loc.start_line && @target_line == loc.end_line
          @target_column.between?(loc.start_column, loc.end_column)
        elsif @target_line == loc.start_line
          @target_column >= loc.start_column
        elsif @target_line == loc.end_line
          @target_column <= loc.end_column
        else
          false
        end
      end
    end
  end
end
