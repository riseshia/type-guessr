# frozen_string_literal: true

require_relative "../types"

module TypeGuessr
  module Core
    module Inference
      # Represents the result of type inference with reasoning
      # Contains the inferred type and why it was inferred
      class Result
        attr_reader :type, :reason, :source

        # @param type [Types::Type] The inferred type
        # @param reason [String] Why this type was inferred
        # @param source [Symbol] Source of the type (:gem, :project, :stdlib, :literal, :unknown)
        def initialize(type, reason, source = :unknown)
          @type = type
          @reason = reason
          @source = source
        end

        def ==(other)
          other.is_a?(Result) &&
            type == other.type &&
            reason == other.reason &&
            source == other.source
        end

        alias eql? ==

        def hash
          [type, reason, source].hash
        end

        def to_s
          "#{type} (#{reason})"
        end
      end
    end
  end
end
