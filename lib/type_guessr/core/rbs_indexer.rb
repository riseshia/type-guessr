# frozen_string_literal: true

require "rbs"
require_relative "method_signature_index"

module TypeGuessr
  module Core
    # Parses RBS files to extract method signature information
    class RBSIndexer
      def initialize(index = MethodSignatureIndex.instance)
        @index = index
      end

      # Index Ruby core library's RBS signatures
      def index_ruby_core
        loader = RBS::EnvironmentLoader.new

        loader.each_signature do |_source, _pathname, _buffer, declarations, _directives|
          process_declarations(declarations)
        end
      rescue StandardError => e
        warn("[TypeGuessr] Error indexing RBS core: #{e.message}")
      end

      # Index project's RBS files from sig/ directory
      def index_project_rbs(dir_path = "sig")
        return unless Dir.exist?(dir_path)

        loader = RBS::EnvironmentLoader.new
        loader.add(path: Pathname(dir_path))

        loader.each_signature do |_source, _pathname, _buffer, declarations, _directives|
          process_declarations(declarations)
        end
      rescue StandardError => e
        warn("[TypeGuessr] Error indexing project RBS: #{e.message}")
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
      # Note: Following ruby-lsp's approach, we only process top-level classes/modules
      # and do not recursively process nested classes.
      def handle_class_or_module(declaration, namespace)
        class_name = declaration.name.name.to_s
        full_class_name = (namespace + [class_name]).join("::")

        # Skip RBS internal types (e.g., RBS::Unnamed::ARGFClass)
        return if full_class_name.start_with?("RBS::Unnamed::")

        # Process only method members (not nested classes/modules)
        # This matches ruby-lsp's behavior
        declaration.members.each do |member|
          case member
          when RBS::AST::Members::MethodDefinition
            handle_method(member, full_class_name)
          end
        end
      end

      # Handle method definitions
      def handle_method(member, class_name)
        method_name = member.name.name.to_s
        is_singleton = member.singleton?

        # Process each overload (RBS supports multiple signatures)
        member.overloads.each do |overload|
          params_array = parse_parameters(overload.method_type)
          return_type_string = type_to_string(overload.method_type.type.return_type)

          @index.add_signature(
            class_name: class_name,
            method_name: method_name,
            params: params_array,
            return_type: return_type_string,
            singleton: is_singleton
          )
        end
      end

      # Parse method parameters into structured array
      # Returns: Array<Hash> with keys :name, :type, :kind
      def parse_parameters(method_type)
        function = method_type.type
        return [] unless function.is_a?(RBS::Types::Function)

        params = []

        # Required positional
        params.concat(function.required_positionals.map do |param|
          {
            name: (param.name || "_").to_s,
            type: type_to_string(param.type),
            kind: :required
          }
        end)

        # Optional positional
        function.optional_positionals.each do |param|
          params << {
            name: (param.name || "_").to_s,
            type: type_to_string(param.type),
            kind: :optional
          }
        end

        # Rest positional
        if function.rest_positionals
          param = function.rest_positionals
          params << {
            name: (param.name || "args").to_s,
            type: type_to_string(param.type),
            kind: :rest
          }
        end

        # Trailing positionals (treated as required)
        function.trailing_positionals&.each do |param|
          params << {
            name: (param.name || "_").to_s,
            type: type_to_string(param.type),
            kind: :required
          }
        end

        # Required keywords
        function.required_keywords&.each do |name, param|
          params << {
            name: name.to_s,
            type: type_to_string(param.type),
            kind: :keyword
          }
        end

        # Optional keywords
        function.optional_keywords&.each do |name, param|
          params << {
            name: name.to_s,
            type: type_to_string(param.type),
            kind: :optional_keyword
          }
        end

        # Rest keywords
        if function.rest_keywords
          param = function.rest_keywords
          params << {
            name: (param.name || "kwargs").to_s,
            type: type_to_string(param.type),
            kind: :keyword_rest
          }
        end

        # Block
        if method_type.block
          params << {
            name: "block",
            type: "Proc",
            kind: :block,
            required: method_type.block.required
          }
        end

        params
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
