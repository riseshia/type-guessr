# frozen_string_literal: true

require "json"
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

# Load CodeIndexAdapter and StandaloneRuntime
require_relative "../../ruby_lsp/type_guessr/code_index_adapter"
require_relative "standalone_runtime"

module TypeGuessr
  module MCP
    # MCP server that exposes type-guessr's inference engine as tools.
    # Indexes the target project on startup and serves type queries via stdio transport.
    #
    # Usage:
    #   server = TypeGuessr::MCP::Server.new(project_path: "/path/to/project")
    #   server.start
    class Server
      # @return [StandaloneRuntime] The runtime used for inference (available after #start)
      attr_reader :runtime

      # @param project_path [String] Path to the Ruby project to analyze
      def initialize(project_path:)
        @project_path = File.expand_path(project_path)
        @runtime = nil
      end

      # Build index and start the MCP server (blocks on stdio transport)
      def start
        warn "[type-guessr] Initializing for project: #{@project_path}"

        index = build_ruby_index
        @runtime = build_runtime(index)
        index_project_files
        start_file_watcher

        server = ::MCP::Server.new(
          name: "type-guessr",
          version: TypeGuessr::VERSION,
          tools: build_tools
        )

        warn "[type-guessr] Server ready"
        transport = ::MCP::Server::Transports::StdioTransport.new(server)
        transport.open
      end

      private def build_ruby_index
        Dir.chdir(@project_path) do
          config = RubyIndexer::Configuration.new
          index = RubyIndexer::Index.new
          uris = config.indexable_uris
          warn "[type-guessr] Indexing #{uris.size} files with RubyIndexer..."
          index.index_all(uris: uris)
          index
        end
      end

      private def build_runtime(ruby_index)
        code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(ruby_index)
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
          type_simplifier: type_simplifier
        )

        StandaloneRuntime.new(
          converter: Core::Converter::PrismConverter.new,
          location_index: Core::Index::LocationIndex.new,
          signature_registry: signature_registry,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry,
          resolver: resolver,
          signature_builder: Core::SignatureBuilder.new(resolver),
          code_index: code_index
        )
      end

      private def index_project_files
        config = Dir.chdir(@project_path) { RubyIndexer::Configuration.new }
        uris = Dir.chdir(@project_path) { config.indexable_uris }
        total = uris.size
        processed = 0

        warn "[type-guessr] Indexing #{total} files with TypeGuessr..."

        uris.each do |uri|
          file_path = uri.respond_to?(:to_standardized_path) ? uri.to_standardized_path : uri.path
          next unless file_path && File.exist?(file_path)

          source = File.read(file_path)
          parsed = Prism.parse(source)
          next unless parsed.value

          @runtime.index_parsed_file(file_path, parsed)
          processed += 1
        rescue StandardError => e
          warn "[type-guessr] Error indexing #{file_path}: #{e.message}"
        end

        @runtime.finalize_index!
        @runtime.preload_signatures!
        warn "[type-guessr] Indexed #{processed}/#{total} files"
      end

      private def start_file_watcher
        @file_watcher = FileWatcher.new(
          project_path: @project_path,
          on_change: method(:handle_file_changes)
        )
        @file_watcher.start
        warn "[type-guessr] File watcher started (polling every 2s)"
      end

      private def handle_file_changes(modified, added, removed)
        (modified + added).each do |file_path|
          source = File.read(file_path)
          parsed = Prism.parse(source)
          @runtime.index_parsed_file(file_path, parsed)
          warn "[type-guessr] Re-indexed: #{file_path}"
        rescue StandardError => e
          warn "[type-guessr] Error re-indexing #{file_path}: #{e.message}"
        end

        removed.each do |file_path|
          @runtime.remove_indexed_file(file_path)
          warn "[type-guessr] Removed from index: #{file_path}"
        end
      end

      private def build_tools
        [build_infer_type_tool, build_get_method_signature_tool, build_search_methods_tool]
      end

      private def build_infer_type_tool
        runtime = @runtime
        to_response = method(:json_response)

        ::MCP::Tool.define(
          name: "infer_type",
          description: "Infer the type of a variable, expression, or method at a specific location in a Ruby file. " \
                       "Returns the guessed type based on heuristic analysis.",
          input_schema: {
            type: "object",
            properties: {
              file_path: { type: "string", description: "Absolute path to the Ruby file" },
              line: { type: "integer", description: "Line number (1-based)" },
              column: { type: "integer", description: "Column number (0-based)" }
            },
            required: %w[file_path line column]
          }
        ) do |file_path:, line:, column:, **|
          to_response.call(runtime.infer_at(file_path, line, column))
        end
      end

      private def build_get_method_signature_tool
        runtime = @runtime
        to_response = method(:json_response)

        ::MCP::Tool.define(
          name: "get_method_signature",
          description: "Get the inferred signature of a method defined in the project. " \
                       "Returns parameter types and return type.",
          input_schema: {
            type: "object",
            properties: {
              class_name: { type: "string", description: "Fully qualified class name (e.g., 'User', 'Admin::User')" },
              method_name: { type: "string", description: "Method name (e.g., 'save', 'initialize')" }
            },
            required: %w[class_name method_name]
          }
        ) do |class_name:, method_name:, **|
          to_response.call(runtime.method_signature(class_name, method_name))
        end
      end

      private def build_search_methods_tool
        runtime = @runtime
        to_response = method(:json_response)

        ::MCP::Tool.define(
          name: "search_methods",
          description: "Search for method definitions in the project. " \
                       "Supports patterns like 'User#save', 'save', or 'Admin::*'.",
          input_schema: {
            type: "object",
            properties: {
              query: { type: "string", description: "Search query (e.g., 'User#save', 'save', 'initialize')" }
            },
            required: %w[query]
          }
        ) do |query:, **|
          to_response.call(runtime.search_methods(query))
        end
      end

      private def json_response(data)
        ::MCP::Tool::Response.new([{ type: "text", text: JSON.generate(data) }])
      end
    end

    # Watches a project directory for .rb file changes using mtime polling.
    # Detects modified, added, and deleted files and invokes a callback.
    #
    # Usage:
    #   watcher = FileWatcher.new(project_path: "/path/to/project", interval: 2) do |modified, added, removed|
    #     modified.each { |f| reindex(f) }
    #     removed.each { |f| remove(f) }
    #   end
    #   watcher.start
    class FileWatcher
      # @param project_path [String] Root directory to watch
      # @param interval [Numeric] Polling interval in seconds (default: 2)
      # @param on_change [Proc] Callback receiving (modified, added, removed) arrays
      def initialize(project_path:, interval: 2, on_change:)
        @project_path = project_path
        @interval = interval
        @on_change = on_change
        @thread = nil
        @running = false
      end

      def start
        @running = true
        @snapshot = take_snapshot
        @thread = Thread.new { poll_loop }
        @thread.abort_on_exception = true
      end

      def stop
        @running = false
        @thread&.join(5)
        @thread = nil
      end

      def running?
        @running && @thread&.alive?
      end

      private

      def poll_loop
        while @running
          sleep(@interval)
          check_changes
        end
      end

      def check_changes
        current = take_snapshot
        previous = @snapshot

        modified = []
        added = []
        removed = []

        current.each do |path, mtime|
          if previous.key?(path)
            modified << path if mtime > previous[path]
          else
            added << path
          end
        end

        previous.each_key do |path|
          removed << path unless current.key?(path)
        end

        @snapshot = current

        return if modified.empty? && added.empty? && removed.empty?

        @on_change.call(modified, added, removed)
      end

      def take_snapshot
        pattern = File.join(@project_path, "**", "*.rb")
        Dir.glob(pattern).each_with_object({}) do |path, hash|
          hash[path] = File.mtime(path)
        rescue Errno::ENOENT
          # File deleted between glob and mtime - skip
        end
      end
    end
  end
end
