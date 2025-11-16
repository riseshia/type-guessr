# frozen_string_literal: true

module RubyLsp
  module Guesser
    # Represents a method parameter with type information
    class Parameter
      attr_reader :name, :type, :kind, :required

      # @param name [String] parameter name
      # @param type [String] parameter type (e.g., "Integer", "String")
      # @param kind [Symbol] parameter kind (:required, :optional, :rest, :keyword, :optional_keyword, :keyword_rest, :block)
      # @param required [Boolean, nil] whether block is required (only for :block kind)
      def initialize(name:, type:, kind:, required: nil)
        @name = name
        @type = type
        @kind = kind
        @required = required
      end

      # Check if this is a positional parameter
      def positional?
        [:required, :optional, :rest].include?(kind)
      end

      # Check if this is a keyword parameter
      def keyword?
        [:keyword, :optional_keyword, :keyword_rest].include?(kind)
      end

      # Check if this is a block parameter
      def block?
        kind == :block
      end

      # Check if this parameter is required
      def required?
        case kind
        when :required, :keyword
          true
        when :block
          required == true
        else
          false
        end
      end

      # Convert to string representation
      def to_s
        case kind
        when :required
          "#{type} #{name}"
        when :optional
          "?#{type} #{name}"
        when :rest
          "*#{type} #{name}"
        when :keyword
          "#{name}: #{type}"
        when :optional_keyword
          "?#{name}: #{type}"
        when :keyword_rest
          "**#{type} #{name}"
        when :block
          required ? "&block" : "?&block"
        end
      end

      # Check equality
      def ==(other)
        other.is_a?(Parameter) &&
          name == other.name &&
          type == other.type &&
          kind == other.kind &&
          required == other.required
      end

      alias eql? ==

      def hash
        [name, type, kind, required].hash
      end
    end
  end
end
