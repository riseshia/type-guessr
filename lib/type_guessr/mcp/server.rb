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
require_relative "../core/type_serializer"
require_relative "../core/logger"
require_relative "../core/cache/gem_signature_cache"
require_relative "../core/cache/gem_dependency_resolver"
require_relative "../core/cache/gem_signature_extractor"

# Load CodeIndexAdapter, StandaloneRuntime, and FileWatcher
require_relative "../../ruby_lsp/type_guessr/code_index_adapter"
require_relative "standalone_runtime"
require_relative "file_watcher"

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
        file_paths = uris.filter_map do |uri|
          uri.respond_to?(:to_standardized_path) ? uri.to_standardized_path : uri.path
        end
        total = file_paths.size

        # Preload RBS signatures first (needed for gem inference)
        @runtime.preload_signatures!

        # Build member_index BEFORE gem inference (duck type resolution needs it)
        @runtime.build_member_index!

        # Try cache-first flow if Gemfile.lock exists
        lockfile_path = File.join(@project_path, "Gemfile.lock")
        if File.exist?(lockfile_path)
          index_with_gem_cache(file_paths, lockfile_path)
        else
          index_all_files(file_paths)
        end

        @runtime.finalize_index!
        warn "[type-guessr] Indexed #{total} files"
      end

      # Cache-first indexing: process gems with cache, then project files
      private def index_with_gem_cache(file_paths, lockfile_path)
        dep_resolver = Core::Cache::GemDependencyResolver.new(lockfile_path)
        partitioned = dep_resolver.partition(file_paths)
        gems = partitioned[:gems]
        project_files = partitioned[:project_files]

        warn "[type-guessr] Partitioned: #{gems.size} gems, #{project_files.size} project files"

        cache = Core::Cache::GemSignatureCache.new
        ordered = dep_resolver.topological_order(gems.keys)

        ordered.each do |gem_name|
          gem_info = gems[gem_name]
          process_gem(gem_name, gem_info, cache)
        end

        # Index project files only
        index_all_files(project_files)
      end

      # Process a single gem: cache hit → load, cache miss → infer → save
      private def process_gem(gem_name, gem_info, cache)
        version = gem_info[:version]
        deps = gem_info[:transitive_deps]
        signature_registry = @runtime.instance_variable_get(:@signature_registry)

        if cache.cached?(gem_name, version, deps)
          data = cache.load(gem_name, version, deps)
          if data
            signature_registry.load_gem_cache(data["instance_methods"], kind: :instance)
            signature_registry.load_gem_cache(data["class_methods"], kind: :class)
            warn "[type-guessr] Loaded cached: #{gem_name}-#{version}"
          else
            warn "[type-guessr] Cache corrupt for #{gem_name}-#{version}, skipping"
          end
        else
          infer_and_cache_gem(gem_name, gem_info, cache, signature_registry)
        end
      end

      # Infer gem signatures using temporary registries
      private def infer_and_cache_gem(gem_name, gem_info, cache, signature_registry)
        version = gem_info[:version]
        files = gem_info[:files]
        deps = gem_info[:transitive_deps]
        code_index = @runtime.instance_variable_get(:@code_index)

        # Phase A: Parse + IR conversion
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        temp_location_index = Core::Index::LocationIndex.new
        temp_method_registry = Core::Registry::MethodRegistry.new(code_index: code_index)
        temp_ivar_registry = Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
        temp_cvar_registry = Core::Registry::ClassVariableRegistry.new
        converter = Core::Converter::PrismConverter.new

        files.each do |file_path|
          next unless File.exist?(file_path)

          parsed = Prism.parse(File.read(file_path))
          next unless parsed.value

          context = Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: temp_location_index,
            method_registry: temp_method_registry,
            ivar_registry: temp_ivar_registry,
            cvar_registry: temp_cvar_registry
          )
          parsed.value.statements&.body&.each { |stmt| converter.convert(stmt, context) }
        rescue StandardError => e
          warn "[type-guessr] Error indexing gem file #{file_path}: #{e.message}"
        end
        temp_location_index.finalize!

        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Phase B: Inference (extract signatures)
        type_simplifier = Core::TypeSimplifier.new(code_index: code_index)
        temp_resolver = Core::Inference::Resolver.new(
          signature_registry,
          code_index: code_index,
          method_registry: temp_method_registry,
          ivar_registry: temp_ivar_registry,
          cvar_registry: temp_cvar_registry,
          type_simplifier: type_simplifier
        )
        temp_builder = Core::SignatureBuilder.new(temp_resolver)

        extractor = Core::Cache::GemSignatureExtractor.new(
          signature_builder: temp_builder,
          method_registry: temp_method_registry,
          location_index: temp_location_index
        )
        signatures = extractor.extract(files)

        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Phase C: Disk save
        cache.save(gem_name, version, deps,
                   instance_methods: signatures[:instance_methods],
                   class_methods: signatures[:class_methods])

        t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Phase D: Registry load
        signature_registry.load_gem_cache(signatures[:instance_methods], kind: :instance)
        signature_registry.load_gem_cache(signatures[:class_methods], kind: :class)

        t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        warn "[type-guessr] Cached #{gem_name}-#{version} (#{files.size} files, " \
             "#{signatures[:instance_methods].size} classes) " \
             "[parse=#{(t1 - t0).round(2)}s infer=#{(t2 - t1).round(2)}s " \
             "save=#{(t3 - t2).round(2)}s load=#{(t4 - t3).round(2)}s]"
      end

      # Index files into the main runtime (project files only)
      private def index_all_files(file_paths)
        file_paths.each do |file_path|
          next unless File.exist?(file_path)

          parsed = Prism.parse(File.read(file_path))
          next unless parsed.value

          @runtime.index_parsed_file(file_path, parsed)
        rescue StandardError => e
          warn "[type-guessr] Error indexing #{file_path}: #{e.message}"
        end
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
          @runtime.refresh_member_index!(URI::Generic.from_path(path: file_path))
          warn "[type-guessr] Re-indexed: #{file_path}"
        rescue StandardError => e
          warn "[type-guessr] Error re-indexing #{file_path}: #{e.message}"
        end

        removed.each do |file_path|
          @runtime.remove_indexed_file(file_path)
          @runtime.refresh_member_index!(URI::Generic.from_path(path: file_path))
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
  end
end
