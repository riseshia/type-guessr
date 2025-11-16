# frozen_string_literal: true

require "rbs"

module RubyLsp
  module Guesser
    # Parses RBS files to extract method signature information
    class RBSSignatureIndexer
      def initialize(index = MethodSignatureIndex.instance)
        @index = index
      end

      # Index Ruby core library's RBS signatures
      def index_ruby_core
        loader = RBS::EnvironmentLoader.new
        env = RBS::Environment.from_loader(loader).resolve_type_names

        loader.each_signature do |_source, _pathname, _buffer, declarations, _directives|
          process_declarations(declarations)
        end
      rescue StandardError => e
        warn("[RubyLspGuesser] Error indexing RBS core: #{e.message}")
      end

      # Index project's RBS files from sig/ directory
      def index_project_rbs(dir_path = "sig")
        return unless Dir.exist?(dir_path)

        loader = RBS::EnvironmentLoader.new
        loader.add(path: Pathname(dir_path))
        env = RBS::Environment.from_loader(loader).resolve_type_names

        loader.each_signature do |_source, _pathname, _buffer, declarations, _directives|
          process_declarations(declarations)
        end
      rescue StandardError => e
        warn("[RubyLspGuesser] Error indexing project RBS: #{e.message}")
      end

      private

      # Process RBS declarations
      def process_declarations(declarations, namespace = [])
        declarations.each do |declaration|
          process_declaration(declaration, namespace)
        end
      end

      # Process a single RBS declaration
      def process_declaration(declaration, namespace)
        case declaration
        when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
          handle_class_or_module(declaration, namespace)
        end
      end

      # Handle class or module declarations
      def handle_class_or_module(declaration, namespace)
        class_name = declaration.name.name.to_s
        full_class_name = (namespace + [class_name]).join("::")

        # Process members (methods, nested classes, etc.)
        declaration.members.each do |member|
          case member
          when RBS::AST::Members::MethodDefinition
            handle_method(member, full_class_name)
          when RBS::AST::Declarations::Class, RBS::AST::Declarations::Module
            # Recursively process nested classes/modules
            process_declaration(member, namespace + [class_name])
          end
        end
      end

      # Handle method definitions
      def handle_method(member, class_name)
        method_name = member.name.name.to_s
        is_singleton = member.singleton?

        # Process each overload (RBS supports multiple signatures)
        member.overloads.each do |overload|
          params_string = format_parameters(overload.method_type)
          return_type_string = type_to_string(overload.method_type.type.return_type)

          @index.add_signature(
            class_name: class_name,
            method_name: method_name,
            params: params_string,
            return_type: return_type_string,
            singleton: is_singleton
          )
        end
      end

      # Format method parameters as a string
      def format_parameters(method_type)
        function = method_type.type
        return "()" unless function.is_a?(RBS::Types::Function)

        params = []

        # Required positional
        function.required_positionals.each do |param|
          type_str = type_to_string(param.type)
          name = param.name || "_"
          params << "#{type_str} #{name}"
        end

        # Optional positional
        function.optional_positionals.each do |param|
          type_str = type_to_string(param.type)
          name = param.name || "_"
          params << "?#{type_str} #{name}"
        end

        # Rest positional
        if function.rest_positionals
          param = function.rest_positionals
          type_str = type_to_string(param.type)
          name = param.name || "args"
          params << "*#{type_str} #{name}"
        end

        # Trailing positionals
        function.trailing_positionals&.each do |param|
          type_str = type_to_string(param.type)
          name = param.name || "_"
          params << "#{type_str} #{name}"
        end

        # Required keywords
        function.required_keywords&.each do |name, param|
          type_str = type_to_string(param.type)
          params << "#{name}: #{type_str}"
        end

        # Optional keywords
        function.optional_keywords&.each do |name, param|
          type_str = type_to_string(param.type)
          params << "?#{name}: #{type_str}"
        end

        # Rest keywords
        if function.rest_keywords
          param = function.rest_keywords
          type_str = type_to_string(param.type)
          name = param.name || "kwargs"
          params << "**#{type_str} #{name}"
        end

        # Block
        if method_type.block
          block = method_type.block
          required = block.required ? "" : "?"
          params << "#{required}{ ... }"
        end

        "(#{params.join(", ")})"
      end

      # Convert RBS::Types to a readable string
      def type_to_string(type)
        case type
        when RBS::Types::Bases::Any
          "untyped"
        when RBS::Types::Bases::Void
          "void"
        when RBS::Types::Bases::Nil
          "nil"
        when RBS::Types::Bases::Bool
          "bool"
        when RBS::Types::Bases::Self
          "self"
        when RBS::Types::ClassInstance
          format_class_instance(type)
        when RBS::Types::Union
          type.types.map { |t| type_to_string(t) }.join(" | ")
        when RBS::Types::Optional
          "#{type_to_string(type.type)}?"
        when RBS::Types::Tuple
          "[#{type.types.map { |t| type_to_string(t) }.join(", ")}]"
        when RBS::Types::Record
          fields = type.fields.map { |k, v| "#{k}: #{type_to_string(v)}" }.join(", ")
          "{ #{fields} }"
        else
          # Fallback: use RBS's own to_s method
          type.to_s
        end
      end

      # Format ClassInstance types (e.g., Array[String], Hash[Symbol, Integer])
      def format_class_instance(type)
        name = type.name.name.to_s
        if type.args.empty?
          name
        else
          args = type.args.map { |arg| type_to_string(arg) }.join(", ")
          "#{name}[#{args}]"
        end
      end
    end
  end
end
