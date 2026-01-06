# frozen_string_literal: true

require "singleton"
require "rbs"
require_relative "types"
require_relative "logger"
require_relative "converter/rbs_converter"

module TypeGuessr
  module Core
    # RBSProvider loads and queries RBS signature information
    # Provides lazy loading of RBS environment for method signatures
    # Uses RBSConverter to convert RBS types to internal type system
    class RBSProvider
      include Singleton

      # Represents a method signature from RBS
      class Signature
        attr_reader :method_type

        def initialize(method_type)
          @method_type = method_type
        end
      end

      def initialize
        @env = nil
        @loader = nil
        @converter = Converter::RBSConverter.new
      end

      # Preload RBS environment (for eager loading during addon activation)
      # @return [self]
      def preload
        ensure_environment_loaded
        self
      end

      # Get method signatures for a class and method name
      # @param class_name [String] the class name
      # @param method_name [String] the method name
      # @return [Array<Signature>] array of method signatures
      def get_method_signatures(class_name, method_name)
        ensure_environment_loaded

        # Build the type name
        type_name = build_type_name(class_name)

        # Use RBS::DefinitionBuilder to get method definitions
        builder = RBS::DefinitionBuilder.new(env: @env)
        definition = builder.build_instance(type_name)

        # Get the method definition
        method_def = definition.methods[method_name.to_sym]
        return [] unless method_def

        # Return all method types (overloads)
        method_def.method_types.map { |mt| Signature.new(mt) }
      rescue RBS::NoTypeFoundError, RBS::NoSuperclassFoundError, RBS::NoMixinFoundError => _e
        # Class not found in RBS
        []
      rescue StandardError => e
        # If anything goes wrong, return empty array
        Logger.error("RBSProvider error", e)
        []
      end

      # Get the return type of a method call with overload resolution
      # @param class_name [String] the receiver class name
      # @param method_name [String] the method name
      # @param arg_types [Array<Types::Type>] argument types for overload matching
      # @return [Types::Type] the return type (Unknown if not found)
      def get_method_return_type(class_name, method_name, arg_types = [])
        signatures = get_method_signatures(class_name, method_name)
        return Types::Unknown.instance if signatures.empty?

        # Find best matching overload based on argument types
        best_match = find_best_overload(signatures, arg_types)
        return_type = best_match.method_type.type.return_type

        @converter.convert(return_type)
      end

      # Get block parameter types for a method
      # @param class_name [String] the receiver class name
      # @param method_name [String] the method name
      # @return [Array<Types::Type>] array of block parameter types (empty if no block)
      def get_block_param_types(class_name, method_name)
        block_sig = find_block_signature(class_name, method_name)
        return [] unless block_sig

        extract_block_param_types(block_sig)
      end

      # Get class method signatures (singleton methods like File.read, Array.new)
      # @param class_name [String] the class name
      # @param method_name [String] the method name
      # @return [Array<Signature>] array of method signatures
      def get_class_method_signatures(class_name, method_name)
        ensure_environment_loaded

        # Build the type name
        type_name = build_type_name(class_name)

        # Use RBS::DefinitionBuilder to get singleton method definitions
        builder = RBS::DefinitionBuilder.new(env: @env)
        definition = builder.build_singleton(type_name)

        # Get the method definition
        method_def = definition.methods[method_name.to_sym]
        return [] unless method_def

        # Return all method types (overloads)
        method_def.method_types.map { |mt| Signature.new(mt) }
      rescue RBS::NoTypeFoundError, RBS::NoSuperclassFoundError, RBS::NoMixinFoundError => _e
        # Class not found in RBS
        []
      rescue StandardError => e
        # If anything goes wrong, return empty array
        Logger.error("RBSProvider class method error", e)
        []
      end

      # Get the return type of a class method call
      # @param class_name [String] the class name
      # @param method_name [String] the method name
      # @param arg_types [Array<Types::Type>] the argument types
      # @return [Types::Type] the return type (Unknown if not found)
      def get_class_method_return_type(class_name, method_name, arg_types = [])
        signatures = get_class_method_signatures(class_name, method_name)
        return Types::Unknown.instance if signatures.empty?

        # Find best matching overload based on argument types
        best_match = find_best_overload(signatures, arg_types)
        return_type = best_match.method_type.type.return_type

        @converter.convert(return_type)
      end

      private

      # Find a method signature that has a block
      # @param class_name [String] the receiver class name
      # @param method_name [String] the method name
      # @return [RBS::MethodType, nil] the method type with block, or nil
      def find_block_signature(class_name, method_name)
        signatures = get_method_signatures(class_name, method_name)
        return nil if signatures.empty?

        # Find the signature with a block
        sig_with_block = signatures.find { |s| s.method_type.block }
        sig_with_block&.method_type
      end

      # Extract block parameter types from a method type
      # @param method_type [RBS::MethodType] the method type
      # @param substitutions [Hash{Symbol => Types::Type}] type variable substitutions (e.g., { Elem: Integer })
      # @return [Array<Types::Type>] array of parameter types
      def extract_block_param_types(method_type, substitutions: {})
        return [] unless method_type.block

        block_func = method_type.block.type
        block_func.required_positionals.flat_map do |param|
          # Handle Tuple types (e.g., [K, V] in Hash#each) by flattening
          raw_types = if param.type.is_a?(RBS::Types::Tuple)
                        param.type.types.map { |t| @converter.convert(t) }
                      else
                        [@converter.convert(param.type)]
                      end
          # Apply substitutions after conversion
          raw_types.map { |t| t.substitute(substitutions) }
        end
      end

      def ensure_environment_loaded
        return if @env

        @loader = RBS::EnvironmentLoader.new

        # Add optional library paths if they exist
        # loader.add(path: Pathname("sig")) if Dir.exist?("sig")

        # Load environment (this automatically loads core/stdlib)
        @env = RBS::Environment.from_loader(@loader).resolve_type_names
      rescue StandardError => e
        Logger.error("Failed to load RBS environment", e)
        # Fallback to empty environment
        @env = RBS::Environment.new
      end

      def build_type_name(class_name)
        # Parse class name to handle namespaced classes like "Foo::Bar"
        parts = class_name.split("::")
        namespace_parts = parts[0...-1]
        name = parts.last

        namespace = if namespace_parts.empty?
                      RBS::Namespace.root
                    else
                      RBS::Namespace.parse(namespace_parts.join("::"))
                    end

        RBS::TypeName.new(name: name.to_sym, namespace: namespace)
      end

      # Find the best matching overload for given argument types
      # @param signatures [Array<Signature>] available overloads
      # @param arg_types [Array<Types::Type>] argument types
      # @return [Signature] best matching signature (first if no match)
      def find_best_overload(signatures, arg_types)
        return signatures.first if arg_types.empty?

        # Score each overload
        scored = signatures.map do |sig|
          score = calculate_overload_score(sig.method_type, arg_types)
          [sig, score]
        end

        # Return best scoring overload, or first if all scores are 0
        best = scored.max_by { |_sig, score| score }
        best[1].positive? ? best[0] : signatures.first
      end

      # Calculate match score for an overload
      # @param method_type [RBS::MethodType] the method type
      # @param arg_types [Array<Types::Type>] argument types
      # @return [Integer] score (higher = better match)
      def calculate_overload_score(method_type, arg_types)
        func = method_type.type
        required = func.required_positionals
        optional = func.optional_positionals
        rest = func.rest_positionals

        # Check argument count
        min_args = required.size
        max_args = rest ? Float::INFINITY : required.size + optional.size
        return 0 unless arg_types.size.between?(min_args, max_args)

        # Score each argument match
        score = 0
        arg_types.each_with_index do |arg_type, i|
          param = if i < required.size
                    required[i]
                  elsif i < required.size + optional.size
                    optional[i - required.size]
                  else
                    rest
                  end

          break unless param

          score += type_match_score(arg_type, param.type)
        end

        score
      end

      # Calculate match score between our type and RBS parameter type
      # @param our_type [Types::Type] our type representation
      # @param rbs_type [RBS::Types::t] RBS type
      # @return [Integer] score (0 = no match, 1 = weak match, 2 = exact match)
      def type_match_score(our_type, rbs_type)
        case rbs_type
        when RBS::Types::ClassInstance
          # Exact class match
          class_name = rbs_type.name.to_s.delete_prefix("::")
          return 2 if types_match_class?(our_type, class_name)

          0
        when RBS::Types::Union
          # Check if our type matches any member
          max_score = rbs_type.types.map { |t| type_match_score(our_type, t) }.max || 0
          max_score.positive? ? 1 : 0
        else
          # Unknown RBS type - give weak match to avoid penalizing
          1
        end
      end

      # Check if our type matches a class name
      # @param our_type [Types::Type] our type
      # @param class_name [String] class name to match
      # @return [Boolean] true if types match
      def types_match_class?(our_type, class_name)
        case our_type
        when Types::ClassInstance
          our_type.name == class_name
        when Types::ArrayType
          class_name == "Array"
        when Types::HashShape
          class_name == "Hash"
        else
          false
        end
      end
    end
  end
end
