# frozen_string_literal: true

require "singleton"
require "rbs"
require_relative "types"

module TypeGuessr
  module Core
    # RBSProvider loads and queries RBS signature information
    # Provides lazy loading of RBS environment for method signatures
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
        warn "RBSProvider error: #{e.class}: #{e.message}" if ENV["DEBUG"]
        []
      end

      # Get the return type of a method call
      # @param class_name [String] the receiver class name
      # @param method_name [String] the method name
      # @return [Types::Type] the return type (Unknown if not found)
      def get_method_return_type(class_name, method_name)
        signatures = get_method_signatures(class_name, method_name)
        return Types::Unknown.instance if signatures.empty?

        # For now, take the first signature's return type
        # TODO: Handle overloads by considering argument types
        first_sig = signatures.first
        return_type = first_sig.method_type.type.return_type

        rbs_type_to_types(return_type)
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

      # Get block parameter types with type variable substitution
      # @param class_name [String] the receiver class name
      # @param method_name [String] the method name
      # @param elem [Types::Type, nil] the element type to substitute for Elem (Array)
      # @param key [Types::Type, nil] the key type to substitute for K (Hash)
      # @param value [Types::Type, nil] the value type to substitute for V (Hash)
      # @return [Array<Types::Type>] array of block parameter types with substitution applied
      def get_block_param_types_with_substitution(class_name, method_name, elem: nil, key: nil, value: nil)
        block_sig = find_block_signature(class_name, method_name)
        return [] unless block_sig

        substitutions = { Elem: elem, K: key, V: value }.compact
        extract_block_param_types(block_sig, substitutions: substitutions)
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
      # @param substitutions [Hash] type variable substitutions (e.g., { Elem: Integer })
      # @return [Array<Types::Type>] array of parameter types
      def extract_block_param_types(method_type, substitutions: {})
        return [] unless method_type.block

        block_func = method_type.block.type
        block_func.required_positionals.map do |param|
          rbs_type_to_types_with_substitution(param.type, substitutions)
        end
      end

      # Convert RBS type to our Types system with substitution support
      # @param rbs_type [RBS::Types::t] the RBS type
      # @param substitutions [Hash] type variable substitutions
      # @return [Types::Type] our type representation
      def rbs_type_to_types_with_substitution(rbs_type, substitutions)
        case rbs_type
        when RBS::Types::Variable
          # Check if we have a substitution for this type variable
          substitutions[rbs_type.name] || Types::Unknown.instance
        when RBS::Types::Tuple
          # Handle tuple types like [K, V] for Hash#each
          element_types = rbs_type.types.map { |t| rbs_type_to_types_with_substitution(t, substitutions) }
          Types::ArrayType.new(Types::Union.new(element_types))
        else
          rbs_type_to_types(rbs_type)
        end
      end

      # Convert RBS type to our Types system
      # @param rbs_type [RBS::Types::t] the RBS type
      # @return [Types::Type] our type representation
      def rbs_type_to_types(rbs_type)
        case rbs_type
        when RBS::Types::ClassInstance
          convert_class_instance(rbs_type)
        when RBS::Types::Union
          types = rbs_type.types.map { |t| rbs_type_to_types(t) }
          Types::Union.new(types)
        when RBS::Types::Variable
          # Type variable (e.g., Elem, T) - can't resolve without context
          Types::Unknown.instance
        when RBS::Types::Bases::Self, RBS::Types::Bases::Instance
          # Return Unknown for now - would need context to resolve
          Types::Unknown.instance
        else
          Types::Unknown.instance
        end
      end

      # Convert RBS ClassInstance to our type system
      # Handles generic types like Array[String], Hash[Symbol, Integer]
      # @param rbs_type [RBS::Types::ClassInstance] the RBS type
      # @return [Types::Type] our type representation
      def convert_class_instance(rbs_type)
        class_name = rbs_type.name.to_s.delete_prefix("::")

        # Handle Array with type parameter
        if class_name == "Array" && rbs_type.args.size == 1
          element_type = rbs_type_to_types(rbs_type.args.first)
          return Types::ArrayType.new(element_type)
        end

        # For other generic types, just return ClassInstance (ignore args for now)
        # TODO: Add HashType support in the future
        Types::ClassInstance.new(class_name)
      end

      def ensure_environment_loaded
        return if @env

        @loader = RBS::EnvironmentLoader.new

        # Add optional library paths if they exist
        # loader.add(path: Pathname("sig")) if Dir.exist?("sig")

        # Load environment (this automatically loads core/stdlib)
        @env = RBS::Environment.from_loader(@loader).resolve_type_names
      rescue StandardError => e
        warn "Failed to load RBS environment: #{e.class}: #{e.message}" if ENV["DEBUG"]
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
    end
  end
end
