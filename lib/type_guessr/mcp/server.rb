# frozen_string_literal: true

require "prism"
require "rbs"
require "mcp"
require "ruby_indexer/ruby_indexer"

# Load ruby-lsp for RubyDocument.locate and NodeContext
require "ruby_lsp/internal"

# Load core components
require_relative "../core/types"
require_relative "../core/node_key_generator"
require_relative "../core/node_context_helper"
require_relative "../core/ir/nodes"
require_relative "../core/index/location_index"
require_relative "../core/converter/prism_converter"
require_relative "../core/converter/rbs_converter"
require_relative "../core/inference/result"
require_relative "../core/inference/resolver"
require_relative "../core/registry/signature_registry"
require_relative "../core/registry/method_registry"
require_relative "../core/registry/instance_variable_registry"
require_relative "../core/registry/class_variable_registry"
require_relative "../core/signature_builder"
require_relative "../core/type_simplifier"
require_relative "../core/logger"

# Load CodeIndexAdapter from ruby_lsp layer (it wraps RubyIndexer)
require_relative "../../ruby_lsp/type_guessr/code_index_adapter"

module TypeGuessr
  module MCP
    class Server
      attr_reader :runtime_adapter

      def initialize(project_path:)
        @project_path = File.expand_path(project_path)
        @server = nil
      end

      def start
        $stderr.puts "[TypeGuessr MCP] Initializing for project: #{@project_path}"

        # Build RubyIndexer index
        index = build_ruby_index
        $stderr.puts "[TypeGuessr MCP] RubyIndexer completed"

        # Build RuntimeAdapter-equivalent components
        @runtime_adapter = build_runtime(index)
        $stderr.puts "[TypeGuessr MCP] Runtime initialized"

        # Index project files with TypeGuessr
        index_project_files(index)
        $stderr.puts "[TypeGuessr MCP] TypeGuessr indexing completed"

        # Create and start MCP server
        @server = ::MCP::Server.new(
          name: "type-guessr",
          version: TypeGuessr::VERSION,
          tools: build_tools,
        )

        $stderr.puts "[TypeGuessr MCP] Server starting on stdio..."
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      private

      def build_ruby_index
        Dir.chdir(@project_path) do
          config = RubyIndexer::Configuration.new
          index = RubyIndexer::Index.new
          uris = config.indexable_uris
          $stderr.puts "[TypeGuessr MCP] Indexing #{uris.size} files with RubyIndexer..."
          index.index_all(uris: uris)
          index
        end
      end

      def build_runtime(ruby_index)
        code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(ruby_index)

        converter = Core::Converter::PrismConverter.new
        location_index = Core::Index::LocationIndex.new
        signature_registry = Core::Registry::SignatureRegistry.instance

        method_registry = Core::Registry::MethodRegistry.new(code_index: code_index)
        ivar_registry = Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
        cvar_registry = Core::Registry::ClassVariableRegistry.new

        type_simplifier = Core::TypeSimplifier.new(code_index: code_index)

        resolver = Core::Inference::Resolver.new(
          signature_registry,
          code_index: code_index,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry,
          type_simplifier: type_simplifier,
        )

        signature_builder = Core::SignatureBuilder.new(resolver)

        StandaloneRuntime.new(
          converter: converter,
          location_index: location_index,
          signature_registry: signature_registry,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry,
          resolver: resolver,
          signature_builder: signature_builder,
          code_index: code_index,
        )
      end

      def index_project_files(ruby_index)
        config = Dir.chdir(@project_path) { RubyIndexer::Configuration.new }
        uris = Dir.chdir(@project_path) { config.indexable_uris }
        total = uris.size
        processed = 0

        $stderr.puts "[TypeGuessr MCP] Indexing #{total} files with TypeGuessr..."

        uris.each do |uri|
          file_path = uri.respond_to?(:to_standardized_path) ? uri.to_standardized_path : uri.path
          next unless file_path && File.exist?(file_path)

          source = File.read(file_path)
          parsed = Prism.parse(source)
          next unless parsed.value

          @runtime_adapter.index_parsed_file(file_path, parsed)
          processed += 1
        rescue StandardError => e
          $stderr.puts "[TypeGuessr MCP] Error indexing #{file_path}: #{e.message}"
        end

        @runtime_adapter.finalize_index!
        @runtime_adapter.preload_signatures!
        $stderr.puts "[TypeGuessr MCP] Indexed #{processed}/#{total} files"
      end

      def build_tools
        runtime = @runtime_adapter

        infer_type_tool = ::MCP::Tool.define(
          name: "infer_type",
          description: "Infer the type of a variable, expression, or method at a specific location in a Ruby file. " \
                       "Returns the guessed type based on heuristic analysis.",
          input_schema: {
            type: "object",
            properties: {
              file_path: {
                type: "string",
                description: "Absolute path to the Ruby file",
              },
              line: {
                type: "integer",
                description: "Line number (1-based)",
              },
              column: {
                type: "integer",
                description: "Column number (0-based)",
              },
            },
            required: %w[file_path line column],
          },
        ) do |file_path:, line:, column:, server_context: nil|
          result = runtime.infer_at(file_path, line, column)

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.generate(result),
          }])
        end

        get_method_signature_tool = ::MCP::Tool.define(
          name: "get_method_signature",
          description: "Get the inferred signature of a method defined in the project. " \
                       "Returns parameter types and return type.",
          input_schema: {
            type: "object",
            properties: {
              class_name: {
                type: "string",
                description: "Fully qualified class name (e.g., 'User', 'Admin::User')",
              },
              method_name: {
                type: "string",
                description: "Method name (e.g., 'save', 'initialize')",
              },
            },
            required: %w[class_name method_name],
          },
        ) do |class_name:, method_name:, server_context: nil|
          result = runtime.method_signature(class_name, method_name)

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.generate(result),
          }])
        end

        search_methods_tool = ::MCP::Tool.define(
          name: "search_methods",
          description: "Search for method definitions in the project. " \
                       "Supports patterns like 'User#save', 'save', or 'Admin::*'.",
          input_schema: {
            type: "object",
            properties: {
              query: {
                type: "string",
                description: "Search query (e.g., 'User#save', 'save', 'initialize')",
              },
            },
            required: %w[query],
          },
        ) do |query:, server_context: nil|
          results = runtime.search_methods(query)

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.generate(results),
          }])
        end

        [infer_type_tool, get_method_signature_tool, search_methods_tool]
      end
    end

    # Standalone runtime that doesn't depend on ruby-lsp's GlobalState
    # Mirrors RuntimeAdapter's interface but for standalone MCP usage
    class StandaloneRuntime
      # Shortcut
      NodeContextHelper = Core::NodeContextHelper

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

      # Index a pre-parsed file (called during initial indexing)
      def index_parsed_file(file_path, prism_result)
        return unless prism_result.value

        @mutex.synchronize do
          @location_index.remove_file(file_path)

          context = Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            ivar_registry: @ivar_registry,
            cvar_registry: @cvar_registry,
          )

          prism_result.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end
        end
      end

      def finalize_index!
        @mutex.synchronize { @location_index.finalize! }
      end

      def preload_signatures!
        @signature_registry.preload
      end

      # Infer type at a specific file location
      # Uses ruby-lsp's RubyDocument.locate for precise node finding
      def infer_at(file_path, line, column)
        file_path = File.expand_path(file_path)

        # Parse with parse_lex to get code_units_cache (required by RubyDocument.locate)
        source = File.read(file_path)
        parse_result = Prism.parse_lex(source)
        return { error: "Failed to parse file" } unless parse_result.value

        ast = parse_result.value.first
        code_units_cache = parse_result.code_units_cache(Encoding::UTF_8)

        # Convert 1-based line/column to byte offset for RubyDocument.locate
        char_position = line_column_to_offset(source, line, column)
        return { error: "Invalid line/column" } unless char_position

        # Use ruby-lsp's node locator — returns NodeContext with nesting, surrounding_method, call_node
        node_context = RubyLsp::RubyDocument.locate(
          ast,
          char_position,
          code_units_cache: code_units_cache,
        )

        prism_node = node_context.node
        return { error: "No node found at position" } unless prism_node

        # Generate node key using the same logic as Hover (via NodeContextHelper)
        exclude_method = prism_node.is_a?(Prism::DefNode)
        scope_id = NodeContextHelper.generate_scope_id(node_context, exclude_method: exclude_method)
        node_hash = NodeContextHelper.generate_node_hash(prism_node, node_context)
        return { error: "Unsupported node type: #{prism_node.class}" } unless node_hash

        node_key = "#{scope_id}:#{node_hash}"

        # Look up IR node
        ir_node = @mutex.synchronize { @location_index.find_by_key(node_key) }
        return { error: "Node not indexed", node_key: node_key, node_type: prism_node.class.name } unless ir_node

        # Handle DefNode
        if ir_node.is_a?(Core::IR::DefNode)
          sig = @mutex.synchronize { @signature_builder.build_from_def_node(ir_node) }
          return {
            type: "method_signature",
            signature: sig.to_s,
            node_type: "DefNode",
          }
        end

        # Handle CallNode - infer return type
        if ir_node.is_a?(Core::IR::CallNode)
          result = @mutex.synchronize { @resolver.infer(ir_node) }
          return {
            type: result.type.to_s,
            method: ir_node.method.to_s,
            reason: result.reason,
            node_type: "CallNode",
          }
        end

        # Infer type for other nodes
        result = @mutex.synchronize { @resolver.infer(ir_node) }
        {
          type: result.type.to_s,
          reason: result.reason,
          node_type: ir_node.class.name.split("::").last,
        }
      rescue StandardError => e
        { error: e.message, backtrace: e.backtrace&.first(3) }
      end

      # Get method signature for a class#method
      def method_signature(class_name, method_name)
        def_node = @mutex.synchronize { @method_registry.lookup(class_name, method_name) }

        unless def_node
          # Try RBS
          sigs = @signature_registry.get_method_signatures(class_name, method_name)
          if sigs.any?
            return {
              source: "rbs",
              signatures: sigs.map { |s| s.method_type.to_s },
            }
          end

          return { error: "Method not found: #{class_name}##{method_name}" }
        end

        sig = @mutex.synchronize { @signature_builder.build_from_def_node(def_node) }
        {
          source: "project",
          signature: sig.to_s,
          class_name: class_name,
          method_name: method_name,
        }
      rescue StandardError => e
        { error: e.message }
      end

      # Search for methods matching a query
      def search_methods(query)
        @mutex.synchronize do
          results = @method_registry.search(query)
          results.map do |class_name, method_name, def_node|
            {
              class_name: class_name,
              method_name: method_name,
              full_name: "#{class_name}##{method_name}",
              location: def_node.loc ? { offset: def_node.loc.offset } : nil,
            }
          end
        end
      rescue StandardError => e
        { error: e.message }
      end

      private

      # Convert 1-based line/0-based column to byte offset
      def line_column_to_offset(source, line, column)
        current_line = 1
        current_offset = 0

        source.each_char do |char|
          return current_offset + column if current_line == line

          if char == "\n"
            current_line += 1
          end
          current_offset += char.bytesize
        end

        # Last line
        current_offset + column if current_line == line
      end
    end
  end
end
