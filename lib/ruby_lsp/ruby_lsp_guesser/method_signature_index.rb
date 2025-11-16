# frozen_string_literal: true

require "singleton"

module RubyLsp
  module Guesser
    # Thread-safe singleton index to store method signatures from RBS
    # Structure:
    # {
    #   "ClassName#method_name" => [
    #     { params: "(Integer id)", return_type: "User" },
    #     { params: "(String email)", return_type: "User" }
    #   ]
    # }
    class MethodSignatureIndex
      include Singleton

      def initialize
        @index = {}
        @mutex = Mutex.new
      end

      # Add a method signature
      # @param class_name [String] the class/module name (e.g., "Array", "User")
      # @param method_name [String] the method name (e.g., "map", "find_user")
      # @param params [String] the parameter signature as a string (e.g., "(Integer id)", "()")
      # @param return_type [String] the return type as a string (e.g., "Array[U]", "User")
      # @param singleton [Boolean] whether this is a singleton method (class method)
      def add_signature(class_name:, method_name:, params:, return_type:, singleton: false)
        @mutex.synchronize do
          key = method_key(class_name, method_name, singleton)
          @index[key] ||= []

          signature = { params: params, return_type: return_type }
          @index[key] << signature unless @index[key].include?(signature)
        end
      end

      # Get all signatures for a method
      # @param class_name [String] the class/module name
      # @param method_name [String] the method name
      # @param singleton [Boolean] whether this is a singleton method
      # @return [Array<Hash>] array of signature hashes with :params and :return_type keys
      def get_signatures(class_name:, method_name:, singleton: false)
        @mutex.synchronize do
          key = method_key(class_name, method_name, singleton)
          @index[key] || []
        end
      end

      # Get only return types for a method (for backward compatibility)
      # @param class_name [String] the class/module name
      # @param method_name [String] the method name
      # @param singleton [Boolean] whether this is a singleton method
      # @return [Array<String>] array of return type strings
      def get_return_types(class_name:, method_name:, singleton: false)
        get_signatures(class_name: class_name, method_name: method_name, singleton: singleton)
          .map { |sig| sig[:return_type] }
          .uniq
      end

      # Clear all index data (useful for testing)
      def clear
        @mutex.synchronize do
          @index.clear
        end
      end

      # Get total number of indexed methods
      def size
        @mutex.synchronize do
          @index.size
        end
      end

      private

      # Generate a unique key for a method
      # @param class_name [String] the class/module name
      # @param method_name [String] the method name
      # @param singleton [Boolean] whether this is a singleton method
      # @return [String] the method key (e.g., "Array#map", "User.find")
      def method_key(class_name, method_name, singleton)
        separator = singleton ? "." : "#"
        "#{class_name}#{separator}#{method_name}"
      end
    end
  end
end
