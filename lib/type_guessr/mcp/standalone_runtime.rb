# frozen_string_literal: true

module TypeGuessr
  module MCP
    # Standalone runtime that mirrors RuntimeAdapter's query interface
    # without depending on ruby-lsp's GlobalState.
    #
    # Provides type inference, method signature lookup, and method search
    # for use by the MCP server. All public query methods are thread-safe.
    class StandaloneRuntime
      NodeContextHelper = Core::NodeContextHelper

      # @param converter [Core::Converter::PrismConverter]
      # @param location_index [Core::Index::LocationIndex]
      # @param signature_registry [Core::Registry::SignatureRegistry]
      # @param method_registry [Core::Registry::MethodRegistry]
      # @param ivar_registry [Core::Registry::InstanceVariableRegistry]
      # @param cvar_registry [Core::Registry::ClassVariableRegistry]
      # @param resolver [Core::Inference::Resolver]
      # @param signature_builder [Core::SignatureBuilder]
      # @param code_index [RubyLsp::TypeGuessr::CodeIndexAdapter]
      def initialize(converter:, location_index:, signature_registry:, method_registry:,
                     ivar_registry:, cvar_registry:, resolver:, signature_builder:, code_index:)
        @converter = converter
        @location_index = location_index
        @signature_registry = signature_registry
        @method_registry = method_registry
        @ivar_registry = ivar_registry
        @cvar_registry = cvar_registry
        @resolver = resolver
        @signature_builder = signature_builder
        @code_index = code_index
        @mutex = Mutex.new
      end

      # Index a pre-parsed file into the IR graph
      # @param file_path [String] Absolute path to the file
      # @param prism_result [Prism::ParseResult] Parsed AST
      def index_parsed_file(file_path, prism_result)
        return unless prism_result.value

        @mutex.synchronize do
          @location_index.remove_file(file_path)
          @resolver.clear_cache

          context = Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            ivar_registry: @ivar_registry,
            cvar_registry: @cvar_registry
          )

          prism_result.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end
        end
      end

      # Remove all indexed data for a file
      # @param file_path [String] Absolute path to the file
      def remove_indexed_file(file_path)
        @mutex.synchronize do
          @location_index.remove_file(file_path)
          @resolver.clear_cache
        end
      end

      # Finalize location index after all files are indexed
      def finalize_index!
        @mutex.synchronize { @location_index.finalize! }
      end

      # Preload RBS signatures for inference
      def preload_signatures!
        @signature_registry.preload
      end

      # Infer type at a specific file location
      # @param file_path [String] Absolute path to the Ruby file
      # @param line [Integer] Line number (1-based)
      # @param column [Integer] Column number (0-based)
      # @return [Hash] Inference result with :type, :reason, :node_type keys, or :error on failure
      def infer_at(file_path, line, column)
        file_path = File.expand_path(file_path)

        source = File.read(file_path)
        parse_result = Prism.parse_lex(source)
        return { error: "Failed to parse file" } unless parse_result.value

        ast = parse_result.value.first
        code_units_cache = parse_result.code_units_cache(Encoding::UTF_8)

        char_position = line_column_to_offset(source, line, column)
        return { error: "Invalid line/column" } unless char_position

        node_context = RubyLsp::RubyDocument.locate(
          ast,
          char_position,
          code_units_cache: code_units_cache
        )

        prism_node = node_context.node
        return { error: "No node found at position" } unless prism_node

        infer_from_prism_node(prism_node, node_context)
      rescue StandardError => e
        { error: e.message, backtrace: e.backtrace&.first(3) }
      end

      # Get method signature for a class#method
      # @param class_name [String] Fully qualified class name (e.g., "User", "Admin::User")
      # @param method_name [String] Method name (e.g., "save", "initialize")
      # @return [Hash] Signature result with :source and :signature keys, or :error on failure
      def method_signature(class_name, method_name)
        def_node = @mutex.synchronize { @method_registry.lookup(class_name, method_name) }

        unless def_node
          sigs = @signature_registry.get_method_signatures(class_name, method_name)
          if sigs.any?
            return {
              source: "rbs",
              signatures: sigs.map { |s| s.method_type.to_s }
            }
          end

          return { error: "Method not found: #{class_name}##{method_name}" }
        end

        sig = @mutex.synchronize { @signature_builder.build_from_def_node(def_node) }
        {
          source: "project",
          signature: sig.to_s,
          class_name: class_name,
          method_name: method_name
        }
      rescue StandardError => e
        { error: e.message }
      end

      # Search for methods matching a query pattern
      # @param query [String] Search query (e.g., "User#save", "save", "initialize")
      # @return [Array<Hash>] Array of matching methods with :class_name, :method_name, :full_name, :location
      def search_methods(query)
        @mutex.synchronize do
          results = @method_registry.search(query)
          results.map do |class_name, method_name, def_node|
            {
              class_name: class_name,
              method_name: method_name,
              full_name: "#{class_name}##{method_name}",
              location: def_node.loc ? { offset: def_node.loc.offset } : nil
            }
          end
        end
      rescue StandardError => e
        { error: e.message }
      end

      private

      # Resolve a Prism AST node to a type inference result
      # @param prism_node [Prism::Node] The AST node at the cursor position
      # @param node_context [RubyLsp::NodeContext] Context from RubyDocument.locate
      # @return [Hash] Inference result
      private def infer_from_prism_node(prism_node, node_context)
        exclude_method = prism_node.is_a?(Prism::DefNode)
        scope_id = NodeContextHelper.generate_scope_id(node_context, exclude_method: exclude_method)
        node_hash = NodeContextHelper.generate_node_hash(prism_node, node_context)
        return { error: "Unsupported node type: #{prism_node.class}" } unless node_hash

        node_key = "#{scope_id}:#{node_hash}"

        ir_node = @mutex.synchronize { @location_index.find_by_key(node_key) }
        return { error: "Node not indexed", node_key: node_key, node_type: prism_node.class.name } unless ir_node

        infer_from_ir_node(ir_node)
      end

      # Infer type from an IR node, dispatching by node type
      # @param ir_node [Core::IR::Node] The indexed IR node
      # @return [Hash] Inference result
      private def infer_from_ir_node(ir_node)
        if ir_node.is_a?(Core::IR::DefNode)
          sig = @mutex.synchronize { @signature_builder.build_from_def_node(ir_node) }
          return {
            type: "method_signature",
            signature: sig.to_s,
            node_type: "DefNode"
          }
        end

        result = @mutex.synchronize { @resolver.infer(ir_node) }

        if ir_node.is_a?(Core::IR::CallNode)
          {
            type: result.type.to_s,
            method: ir_node.method.to_s,
            reason: result.reason,
            node_type: "CallNode"
          }
        else
          {
            type: result.type.to_s,
            reason: result.reason,
            node_type: ir_node.class.name.split("::").last
          }
        end
      end

      # Convert 1-based line / 0-based column to byte offset
      # @param source [String] Source code
      # @param line [Integer] Line number (1-based)
      # @param column [Integer] Column number (0-based)
      # @return [Integer, nil] Byte offset, or nil if line/column is out of bounds
      private def line_column_to_offset(source, line, column)
        current_line = 1
        current_offset = 0

        source.each_char do |char|
          return current_offset + column if current_line == line

          current_line += 1 if char == "\n"
          current_offset += char.bytesize
        end

        # Last line (no trailing newline)
        current_offset + column if current_line == line
      end
    end
  end
end
