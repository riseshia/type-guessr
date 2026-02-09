# frozen_string_literal: true

require "singleton"
require "rbs"
require_relative "../types"
require_relative "../logger"
require_relative "../converter/rbs_converter"

module TypeGuessr
  module Core
    module Registry
      # Preloads stdlib RBS signatures and provides O(1) hash lookup
      # Singleton to ensure RBS is loaded only once across all usages
      class SignatureRegistry
        include Singleton

        # Represents a method signature entry from RBS
        # Handles overload resolution and type conversion
        class MethodEntry
          # @param method_types [Array<RBS::MethodType>] RBS method type definitions
          # @param converter [Converter::RBSConverter] RBS to internal type converter
          def initialize(method_types, converter)
            @method_types = method_types
            @converter = converter
          end

          # Get the return type with overload resolution
          # @param arg_types [Array<Types::Type>] argument types for overload matching
          # @return [Types::Type] the return type
          def return_type(arg_types = [])
            best_match = find_best_overload(arg_types)
            @converter.convert(best_match.type.return_type)
          end

          # Get block parameter types for this method
          # @return [Array<Types::Type>] array of block parameter types (empty if no block)
          def block_param_types
            return @block_param_types if defined?(@block_param_types)

            @block_param_types = compute_block_param_types
          end

          # Get raw method signatures for display
          # @return [Array<RBS::MethodType>] raw RBS method types
          def signatures
            @method_types
          end

          private def compute_block_param_types
            # Find the signature with a block
            sig_with_block = @method_types.find(&:block)
            return [] unless sig_with_block

            extract_block_param_types(sig_with_block)
          end

          private def extract_block_param_types(method_type)
            return [] unless method_type.block

            block_func = method_type.block.type
            block_func.required_positionals.flat_map do |param|
              # Handle Tuple types (e.g., [K, V] in Hash#each) by flattening
              if param.type.is_a?(RBS::Types::Tuple)
                param.type.types.map { |t| @converter.convert(t) }
              else
                [@converter.convert(param.type)]
              end
            end
          end

          # Find the best matching overload for given argument types
          # @param arg_types [Array<Types::Type>] argument types
          # @return [RBS::MethodType] best matching method type (first if no match)
          private def find_best_overload(arg_types)
            return @method_types.first if arg_types.empty?

            # Score each overload
            scored = @method_types.map do |method_type|
              score = calculate_overload_score(method_type, arg_types)
              [method_type, score]
            end

            # Return best scoring overload, or first if all scores are 0
            best = scored.max_by { |_mt, score| score }
            best[1].positive? ? best[0] : @method_types.first
          end

          # Calculate match score for an overload
          private def calculate_overload_score(method_type, arg_types)
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
          private def type_match_score(our_type, rbs_type)
            case rbs_type
            when RBS::Types::ClassInstance
              class_name = rbs_type.name.to_s.delete_prefix("::")
              return 2 if types_match_class?(our_type, class_name)

              0
            when RBS::Types::Union
              max_score = rbs_type.types.map { |t| type_match_score(our_type, t) }.max || 0
              max_score.positive? ? 1 : 0
            else
              # Unknown RBS type - give weak match to avoid penalizing
              1
            end
          end

          private def types_match_class?(our_type, class_name)
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

        def initialize
          @instance_methods = {} # { "String" => { "upcase" => MethodEntry } }
          @class_methods = {}    # { "File" => { "read" => MethodEntry } }
          @converter = Converter::RBSConverter.new
          @preloaded = false
        end

        # Preload stdlib RBS signatures
        # @return [self]
        def preload
          return self if @preloaded

          load_stdlib_rbs
          @preloaded = true
          self
        end

        # Check if preloading is complete
        # @return [Boolean]
        def preloaded?
          @preloaded
        end

        # Look up instance method entry
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @return [MethodEntry, nil] method entry or nil if not found
        def lookup(class_name, method_name)
          @instance_methods.dig(class_name, method_name)
        end

        # Look up class method entry
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @return [MethodEntry, nil] method entry or nil if not found
        def lookup_class_method(class_name, method_name)
          @class_methods.dig(class_name, method_name)
        end

        # Get method return type (convenience method matching old SignatureProvider API)
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @param arg_types [Array<Types::Type>] argument types for overload matching
        # @return [Types::Type] the return type (Unknown if not found)
        def get_method_return_type(class_name, method_name, arg_types = [])
          entry = lookup(class_name, method_name)
          return Types::Unknown.instance unless entry

          entry.return_type(arg_types)
        end

        # Get class method return type (convenience method matching old SignatureProvider API)
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @param arg_types [Array<Types::Type>] argument types for overload matching
        # @return [Types::Type] the return type (Unknown if not found)
        def get_class_method_return_type(class_name, method_name, arg_types = [])
          entry = lookup_class_method(class_name, method_name)
          return Types::Unknown.instance unless entry

          entry.return_type(arg_types)
        end

        # Get block parameter types for a method
        # @param class_name [String] the receiver class name
        # @param method_name [String] the method name
        # @return [Array<Types::Type>] array of block parameter types (empty if no block)
        def get_block_param_types(class_name, method_name)
          entry = lookup(class_name, method_name)
          return [] unless entry

          entry.block_param_types
        end

        # Get method signatures for hover display
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @return [Array<Signature>] wrapped signatures for compatibility
        def get_method_signatures(class_name, method_name)
          entry = lookup(class_name, method_name)
          return [] unless entry

          entry.signatures.map { |mt| Signature.new(mt) }
        end

        # Get class method signatures for hover display
        # @param class_name [String] the class name
        # @param method_name [String] the method name
        # @return [Array<Signature>] wrapped signatures for compatibility
        def get_class_method_signatures(class_name, method_name)
          entry = lookup_class_method(class_name, method_name)
          return [] unless entry

          entry.signatures.map { |mt| Signature.new(mt) }
        end

        # Wrapper for RBS method type (for compatibility with existing code)
        class Signature
          attr_reader :method_type

          def initialize(method_type)
            @method_type = method_type
          end
        end

        private def load_stdlib_rbs
          loader = RBS::EnvironmentLoader.new
          env = RBS::Environment.from_loader(loader).resolve_type_names
          builder = RBS::DefinitionBuilder.new(env: env)

          env.class_decls.each_key do |type_name|
            load_class_definitions(type_name, builder)
          end
        rescue StandardError => e
          Logger.error("Failed to preload RBS environment", e)
        end

        private def load_class_definitions(type_name, builder)
          class_name = type_name.to_s.delete_prefix("::")

          # Load instance methods
          begin
            definition = builder.build_instance(type_name)
            @instance_methods[class_name] = build_method_entries(definition)
          rescue RBS::NoTypeFoundError, RBS::NoSuperclassFoundError, RBS::NoMixinFoundError
            # Skip classes with missing dependencies
          end

          # Load class methods (singleton)
          begin
            definition = builder.build_singleton(type_name)
            @class_methods[class_name] = build_method_entries(definition)
          rescue RBS::NoTypeFoundError, RBS::NoSuperclassFoundError, RBS::NoMixinFoundError
            # Skip classes with missing dependencies
          end
        end

        private def build_method_entries(definition)
          # RBS methods hash uses Symbol keys, but we use String keys for lookup
          definition.methods.to_h do |method_name, method_def|
            [method_name.to_s, MethodEntry.new(method_def.method_types, @converter)]
          end
        end
      end
    end
  end
end
