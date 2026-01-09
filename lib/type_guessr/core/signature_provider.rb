# frozen_string_literal: true

require_relative "types"

module TypeGuessr
  module Core
    # SignatureProvider aggregates multiple type sources for method signature lookups
    # Uses priority-based resolution: first non-Unknown result wins
    #
    # @example
    #   provider = SignatureProvider.new
    #   provider.add_provider(ProjectRBSProvider.new, priority: :high)
    #   provider.add_provider(RBSProvider.instance)
    #
    #   return_type = provider.get_method_return_type("String", "upcase")
    class SignatureProvider
      # @param providers [Array<#get_method_return_type>] Providers in priority order (first = highest)
      def initialize(providers = [])
        @providers = providers.dup
      end

      # Add a provider to the chain
      # @param provider [#get_method_return_type] Provider implementing the signature protocol
      # @param priority [:high, :low] Priority level (:high = first, :low = last)
      def add_provider(provider, priority: :low)
        case priority
        when :high
          @providers.unshift(provider)
        when :low
          @providers.push(provider)
        end
      end

      # Get instance method return type with overload resolution
      # @param class_name [String] Class name (e.g., "String", "Array")
      # @param method_name [String] Method name (e.g., "upcase", "map")
      # @param arg_types [Array<Types::Type>] Argument types for overload matching
      # @return [Types::Type] Return type (Unknown if not found in any provider)
      def get_method_return_type(class_name, method_name, arg_types = [])
        @providers.each do |provider|
          result = provider.get_method_return_type(class_name, method_name, arg_types)
          return result unless result.is_a?(Types::Unknown)
        end
        Types::Unknown.instance
      end

      # Get class method return type (e.g., File.read, Array.new)
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @param arg_types [Array<Types::Type>] Argument types for overload matching
      # @return [Types::Type] Return type (Unknown if not found in any provider)
      def get_class_method_return_type(class_name, method_name, arg_types = [])
        @providers.each do |provider|
          result = provider.get_class_method_return_type(class_name, method_name, arg_types)
          return result unless result.is_a?(Types::Unknown)
        end
        Types::Unknown.instance
      end

      # Get block parameter types for a method
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [Array<Types::Type>] Block parameter types (empty if no block or not found)
      def get_block_param_types(class_name, method_name)
        @providers.each do |provider|
          result = provider.get_block_param_types(class_name, method_name)
          return result unless result.empty?
        end
        []
      end

      # Get method signatures for hover display
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [Array<Signature>] Method signatures (empty if not found)
      def get_method_signatures(class_name, method_name)
        @providers.each do |provider|
          next unless provider.respond_to?(:get_method_signatures)

          result = provider.get_method_signatures(class_name, method_name)
          return result unless result.empty?
        end
        []
      end

      # Get class method signatures for hover display (e.g., File.exist?, Dir.pwd)
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [Array<Signature>] Method signatures (empty if not found)
      def get_class_method_signatures(class_name, method_name)
        @providers.each do |provider|
          next unless provider.respond_to?(:get_class_method_signatures)

          result = provider.get_class_method_signatures(class_name, method_name)
          return result unless result.empty?
        end
        []
      end
    end
  end
end
