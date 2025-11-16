# frozen_string_literal: true

require_relative "parameter"

module RubyLsp
  module Guesser
    # Represents a method signature with parameters and return type
    class MethodSignature
      attr_reader :params, :return_type

      # @param params [Array<Parameter>] array of Parameter objects
      # @param return_type [String] return type as string (e.g., "User", "Array[String]")
      def initialize(params:, return_type:)
        @params = params.is_a?(Array) ? params : []
        @return_type = return_type
      end

      # Get positional parameters only
      # @return [Array<Parameter>]
      def positional_params
        @params.select(&:positional?)
      end

      # Get keyword parameters only
      # @return [Array<Parameter>]
      def keyword_params
        @params.select(&:keyword?)
      end

      # Get block parameter
      # @return [Parameter, nil]
      def block_param
        @params.find(&:block?)
      end

      # Check if this signature has a block parameter
      # @return [Boolean]
      def has_block?
        !block_param.nil?
      end

      # Check if block is required
      # @return [Boolean]
      def block_required?
        block_param&.required? || false
      end

      # Get count of required positional parameters
      # @return [Integer]
      def required_positional_count
        positional_params.count(&:required?)
      end

      # Convert to human-readable string
      # @return [String] e.g., "(Integer id, String name) -> User"
      def to_s
        param_str = if @params.empty?
                      "()"
                    else
                      "(#{@params.map(&:to_s).join(", ")})"
                    end
        "#{param_str} -> #{return_type}"
      end

      # Check equality
      def ==(other)
        other.is_a?(MethodSignature) &&
          params == other.params &&
          return_type == other.return_type
      end

      alias eql? ==

      def hash
        [params, return_type].hash
      end

      # Convert to hash (for backward compatibility with existing code)
      # @return [Hash]
      def to_h
        {
          params: @params.map { |p| { name: p.name, type: p.type, kind: p.kind, required: p.required }.compact },
          return_type: @return_type
        }
      end

      # Create from hash (for backward compatibility)
      # @param hash [Hash] hash with :params and :return_type keys
      # @return [MethodSignature]
      def self.from_hash(hash)
        params = (hash[:params] || []).map do |param_hash|
          Parameter.new(**param_hash.slice(:name, :type, :kind, :required))
        end
        new(params: params, return_type: hash[:return_type])
      end
    end
  end
end
