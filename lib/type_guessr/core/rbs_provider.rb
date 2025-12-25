# frozen_string_literal: true

require "rbs"

module TypeGuessr
  module Core
    # RBSProvider loads and queries RBS signature information
    # Provides lazy loading of RBS environment for method signatures
    class RBSProvider
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

      private

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
