# frozen_string_literal: true

require "prism"
require_relative "../../type_guessr/core/converter/prism_converter"
require_relative "../../type_guessr/core/index/location_index"
require_relative "../../type_guessr/core/registry/method_registry"
require_relative "../../type_guessr/core/registry/instance_variable_registry"
require_relative "../../type_guessr/core/registry/class_variable_registry"
require_relative "../../type_guessr/core/registry/signature_registry"
require_relative "../../type_guessr/core/inference/resolver"
require_relative "../../type_guessr/core/signature_builder"
require_relative "../../type_guessr/core/type_simplifier"
require_relative "../../type_guessr/core/node_context_helper"
require_relative "../../type_guessr/core/cache/gem_signature_cache"
require_relative "../../type_guessr/core/cache/gem_dependency_resolver"
require_relative "../../type_guessr/core/cache/gem_signature_extractor"
require_relative "code_index_adapter"
require_relative "type_inferrer"

module RubyLsp
  module TypeGuessr
    # RuntimeAdapter manages the IR graph and inference for TypeGuessr
    # Converts files to IR graphs and provides type inference
    class RuntimeAdapter
      attr_reader :signature_registry, :location_index, :resolver, :method_registry

      def initialize(global_state, message_queue = nil)
        @global_state = global_state
        @message_queue = message_queue
        @converter = ::TypeGuessr::Core::Converter::PrismConverter.new
        @location_index = ::TypeGuessr::Core::Index::LocationIndex.new
        @signature_registry = ::TypeGuessr::Core::Registry::SignatureRegistry.instance
        @indexing_completed = false
        @mutex = Mutex.new
        @original_type_inferrer = nil

        # Create CodeIndexAdapter wrapping RubyIndexer
        @code_index = CodeIndexAdapter.new(global_state&.index)

        # Create method registry with code_index for inheritance lookup
        @method_registry = ::TypeGuessr::Core::Registry::MethodRegistry.new(
          code_index: @code_index
        )

        # Create variable registries (ivar needs code_index for inheritance lookup)
        @ivar_registry = ::TypeGuessr::Core::Registry::InstanceVariableRegistry.new(
          code_index: @code_index
        )
        @cvar_registry = ::TypeGuessr::Core::Registry::ClassVariableRegistry.new

        # Create type simplifier with code_index for inheritance lookup
        type_simplifier = ::TypeGuessr::Core::TypeSimplifier.new(
          code_index: @code_index
        )

        # Create resolver with signature_registry and registries
        @resolver = ::TypeGuessr::Core::Inference::Resolver.new(
          @signature_registry,
          code_index: @code_index,
          method_registry: @method_registry,
          ivar_registry: @ivar_registry,
          cvar_registry: @cvar_registry,
          type_simplifier: type_simplifier
        )

        # Build method signatures from DefNodes using resolver
        @signature_builder = ::TypeGuessr::Core::SignatureBuilder.new(@resolver)
      end

      # Swap ruby-lsp's TypeInferrer with TypeGuessr's custom implementation
      # This enhances Go to Definition and other features with heuristic type inference
      def swap_type_inferrer
        return unless @global_state.respond_to?(:type_inferrer)

        @original_type_inferrer = @global_state.type_inferrer
        custom_inferrer = TypeInferrer.new(@global_state.index, self)
        @global_state.instance_variable_set(:@type_inferrer, custom_inferrer)
        log_message("TypeInferrer swapped for enhanced type inference")
      rescue StandardError => e
        log_message("Failed to swap TypeInferrer: #{e.message}")
      end

      # Restore the original TypeInferrer
      def restore_type_inferrer
        return unless @original_type_inferrer

        @global_state.instance_variable_set(:@type_inferrer, @original_type_inferrer)
        @original_type_inferrer = nil
        log_message("TypeInferrer restored")
      rescue StandardError => e
        log_message("Failed to restore TypeInferrer: #{e.message}")
      end

      # Index a file by converting its Prism AST to IR graph
      # @param uri [URI::Generic] File URI
      # @param document [RubyLsp::Document] Document to index
      def index_file(uri, document)
        file_path = uri.to_standardized_path
        return unless file_path

        parsed = document.parse_result

        index_file_with_prism_result(file_path, parsed)
      rescue StandardError => e
        log_message("Error in index_file #{uri}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      end

      # Index source code directly (for testing)
      # @param uri_string [String] File URI as string
      # @param source [String] Source code to index
      def index_source(uri_string, source)
        require "uri"
        uri = URI(uri_string)
        file_path = uri.respond_to?(:to_standardized_path) ? uri.to_standardized_path : uri.path
        file_path ||= uri_string.sub(%r{^file://}, "")
        return unless file_path

        parsed = Prism.parse(source)

        index_file_with_prism_result(file_path, parsed)
      end

      # Build member_index for duck type resolution (exposed for testing)
      def build_member_index!
        @code_index.build_member_index!
      end

      # Remove indexed data for a file
      # @param file_path [String] File path to remove
      def remove_indexed_file(file_path)
        @mutex.synchronize do
          @location_index.remove_file(file_path)
          @method_registry.remove_file(file_path)
          @ivar_registry.remove_file(file_path)
          @cvar_registry.remove_file(file_path)
          @resolver.clear_cache
          @code_index.refresh_member_index!(URI::Generic.from_path(path: file_path))
        end
      end

      # Find IR node by its unique key
      # @param node_key [String] The node key (scope_id:node_hash)
      # @return [TypeGuessr::Core::IR::Node, nil] IR node or nil if not found
      def find_node_by_key(node_key)
        @mutex.synchronize do
          @location_index.find_by_key(node_key)
        end
      end

      # Infer type for an IR node
      # @param node [TypeGuessr::Core::IR::Node] IR node
      # @return [TypeGuessr::Core::Inference::Result] Inference result
      def infer_type(node)
        @mutex.synchronize do
          @resolver.infer(node)
        end
      end

      # Build a MethodSignature from a DefNode
      # @param def_node [TypeGuessr::Core::IR::DefNode] Method definition node
      # @return [TypeGuessr::Core::Types::MethodSignature] Structured method signature
      def build_method_signature(def_node)
        @mutex.synchronize do
          @signature_builder.build_from_def_node(def_node)
        end
      end

      # Build a constructor signature for Class.new calls
      # Maps .new to #initialize and returns ClassName instance
      # Checks project methods first, then falls back to RBS
      # @param class_name [String] Class name (e.g., "User")
      # @return [Hash] { signature: MethodSignature, source: :project | :rbs | :default }
      def build_constructor_signature(class_name)
        @mutex.synchronize do
          instance_type = ::TypeGuessr::Core::Types::ClassInstance.for(class_name)

          # 1. Try project methods first
          init_def = @method_registry.lookup(class_name, "initialize")
          if init_def
            sig = @signature_builder.build_from_def_node(init_def)
            return {
              signature: ::TypeGuessr::Core::Types::MethodSignature.new(sig.params, instance_type),
              source: :project
            }
          end

          # 2. Fall back to RBS
          rbs_sigs = @signature_registry.get_method_signatures(class_name, "initialize")
          if rbs_sigs.any?
            return {
              rbs_signature: rbs_sigs.first,
              source: :rbs
            }
          end

          # 3. Default: no initialize found
          {
            signature: ::TypeGuessr::Core::Types::MethodSignature.new([], instance_type),
            source: :default
          }
        end
      end

      # Look up a method definition by class name and method name
      # @param class_name [String] Class name (e.g., "User", "Admin::User")
      # @param method_name [String] Method name (e.g., "initialize", "save")
      # @return [TypeGuessr::Core::IR::DefNode, nil] DefNode or nil if not found
      def lookup_method(class_name, method_name)
        @mutex.synchronize do
          @method_registry.lookup(class_name, method_name)
        end
      end

      # Start background indexing of all project files
      def start_indexing
        Thread.new do
          index = @global_state.index

          # Wait for Ruby LSP's initial indexing to complete
          log_message("Waiting for Ruby LSP initial indexing to complete...")
          sleep(0.1) until index.initial_indexing_completed
          log_message("Ruby LSP indexing completed.")

          # Preload RBS signatures while waiting for other addons to finish
          @signature_registry.preload

          # Wait for other addons (ruby-lsp-rails, etc.) to finish registering entries
          wait_for_index_stabilization(index)

          # Build member_index AFTER all entries are registered
          @code_index.build_member_index!
          log_message("Member index built.")

          # Get all indexable files (project + gems)
          indexable_uris = index.configuration.indexable_uris
          file_paths = indexable_uris.filter_map(&:to_standardized_path)
          total = file_paths.size
          log_message("Found #{total} files to process.")

          # Try cache-first flow if Gemfile.lock exists
          lockfile_path = find_lockfile
          result = nil
          if lockfile_path
            result = index_with_gem_cache(file_paths, lockfile_path)
          else
            index_all_files(file_paths)
          end
          # Connect on-demand inference callback for Unguessed gem methods
          @signature_registry.on_demand_inferrer = method(:infer_gem_file_on_demand)

          @indexing_completed = true

          # Background inference: fully infer gems that have Unguessed entries (opt-in)
          background_infer_gems(result[:unguessed_gems], result[:cache]) if Config.background_gem_indexing? && result && result[:unguessed_gems].any?
        rescue StandardError => e
          log_message("Error during file indexing: #{e.message}\n#{e.backtrace.first(10).join("\n")}")
          @indexing_completed = true
        end
      end

      # Check if initial indexing has completed
      def indexing_completed?
        @indexing_completed
      end

      # Get statistics about the index
      # @return [Hash] Statistics
      def stats
        @location_index.stats
      end

      # Get all methods for a specific class (thread-safe)
      # @param class_name [String] Class name
      # @return [Hash<String, DefNode>] Methods hash
      def methods_for_class(class_name)
        @mutex.synchronize { @method_registry.methods_for_class(class_name) }
      end

      # Search for methods matching a pattern (thread-safe)
      # @param query [String] Search query (e.g., "User#save" or "save")
      # @return [Array<Hash>] Array of method info hashes
      def search_project_methods(query)
        @mutex.synchronize do
          @method_registry.search(query).map do |class_name, method_name, def_node|
            {
              class_name: class_name,
              method_name: method_name,
              full_name: "#{class_name}##{method_name}",
              node_key: def_node.node_key(class_name),
              location: { line: def_node.loc&.line }
            }
          end
        end
      end

      # Resolve a short constant name to fully qualified name
      # @param short_name [String] Short constant name
      # @param nesting [Array<String>] Nesting context
      # @return [String, nil] Fully qualified name or nil
      def resolve_constant_name(short_name, nesting)
        @code_index&.resolve_constant_name(short_name, nesting)
      end

      # Look up RBS method signatures with owner resolution
      # Finds the actual class that defines the method (e.g., Object for #tap)
      # @param class_name [String] Receiver class name
      # @param method_name [String] Method name
      # @return [Hash] { signatures: Array<Signature>, owner: String }
      def get_rbs_method_signatures(class_name, method_name)
        @mutex.synchronize do
          # Find actual owner class (e.g., Object for tap on MyClass)
          owner_class = @code_index&.instance_method_owner(class_name, method_name) || class_name

          signatures = @signature_registry.get_method_signatures(owner_class, method_name)
          { signatures: signatures, owner: owner_class }
        end
      end

      # Look up RBS class method signatures with owner resolution
      # @param class_name [String] Class name
      # @param method_name [String] Method name
      # @return [Hash] { signatures: Array<Signature>, owner: String }
      def get_rbs_class_method_signatures(class_name, method_name)
        @mutex.synchronize do
          # Find actual owner class for class methods
          owner_class = @code_index&.class_method_owner(class_name, method_name) || class_name

          # Convert singleton format (e.g., "File::<Class:File>") to simple class name ("File")
          # SignatureRegistry expects simple class names for RBS lookup
          owner_class = extract_class_from_singleton(owner_class)

          signatures = @signature_registry.get_class_method_signatures(owner_class, method_name)
          { signatures: signatures, owner: owner_class }
        end
      end

      # Cache-first indexing: process gems with cache, then project files
      # @return [Hash] { cache:, unguessed_gems: [...] }
      private def index_with_gem_cache(file_paths, lockfile_path)
        resolver_class = ::TypeGuessr::Core::Cache::GemDependencyResolver
        dep_resolver = resolver_class.new(lockfile_path)
        partitioned = dep_resolver.partition(file_paths)
        gems = partitioned[:gems]
        project_files = partitioned[:project_files]

        log_message("Partitioned: #{gems.size} gems, #{project_files.size} project files.")

        cache = ::TypeGuessr::Core::Cache::GemSignatureCache.new
        ordered = dep_resolver.topological_order(gems.keys)

        # Process each gem in dependency order, collecting those needing background inference
        unguessed_gems = []
        ordered.each do |gem_name|
          gem_info = gems[gem_name]
          needs_inference = process_gem(gem_name, gem_info, cache)
          unguessed_gems << { name: gem_name, info: gem_info } if needs_inference
        end

        # Index project files into main registries
        index_all_files(project_files)

        { cache: cache, unguessed_gems: unguessed_gems }
      end

      # Process a single gem: cache hit → load, cache miss → save unguessed cache
      # @return [Boolean] Whether background inference is needed for this gem
      private def process_gem(gem_name, gem_info, cache)
        version = gem_info[:version]
        deps = gem_info[:transitive_deps]
        file_count = gem_info[:files].size

        log_message("Processing #{gem_name}-#{version} (#{file_count} files)...")

        if cache.cached?(gem_name, version, deps)
          data = load_gem_from_cache(gem_name, version, deps, cache)
          return false unless data

          # Previously timed out — don't retry background inference
          return false if data["inference_timeout"]

          !data["fully_inferred"]
        else
          save_unguessed_cache(gem_name, gem_info, cache)
          true
        end
      end

      # Load gem signatures from disk cache into SignatureRegistry
      # @return [Hash, nil] Loaded cache data or nil on failure
      private def load_gem_from_cache(gem_name, version, deps, cache)
        data = cache.load(gem_name, version, deps)
        unless data
          log_message("Cache corrupt for #{gem_name}-#{version}, skipping.")
          return nil
        end

        @signature_registry.load_gem_cache(data["instance_methods"], kind: :instance)
        @signature_registry.load_gem_cache(data["class_methods"], kind: :class)
        log_message(
          "Loaded cached signatures for #{gem_name}-#{version} " \
          "(fully_inferred=#{data["fully_inferred"]}, inference_timeout=#{data["inference_timeout"]})."
        )
        data
      end

      # Infer gem method signatures using temporary registries, then cache
      # @return [Hash, nil] { instance_methods:, class_methods: } or nil on error
      private def infer_and_cache_gem(gem_name, gem_info, cache)
        version = gem_info[:version]
        files = gem_info[:files]
        deps = gem_info[:transitive_deps]

        # Phase A: Parse + IR conversion
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        temp_location_index = ::TypeGuessr::Core::Index::LocationIndex.new
        temp_method_registry = ::TypeGuessr::Core::Registry::MethodRegistry.new(code_index: @code_index)
        temp_ivar_registry = ::TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: @code_index)
        temp_cvar_registry = ::TypeGuessr::Core::Registry::ClassVariableRegistry.new

        converter = ::TypeGuessr::Core::Converter::PrismConverter.new
        files.each do |file_path|
          parse_and_index_file(file_path, converter, temp_location_index,
                               temp_method_registry, temp_ivar_registry, temp_cvar_registry)
        end
        temp_location_index.finalize!

        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Phase B: Inference (extract signatures)
        type_simplifier = ::TypeGuessr::Core::TypeSimplifier.new(code_index: @code_index)
        temp_resolver = ::TypeGuessr::Core::Inference::Resolver.new(
          @signature_registry,
          code_index: @code_index,
          method_registry: temp_method_registry,
          ivar_registry: temp_ivar_registry,
          cvar_registry: temp_cvar_registry,
          type_simplifier: type_simplifier
        )
        temp_builder = ::TypeGuessr::Core::SignatureBuilder.new(temp_resolver)

        extractor = ::TypeGuessr::Core::Cache::GemSignatureExtractor.new(
          signature_builder: temp_builder,
          method_registry: temp_method_registry,
          location_index: temp_location_index
        )
        timeout = Config.gem_inference_timeout
        signatures = extractor.extract(files, timeout: timeout)

        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Inference timed out — save as unguessed with timeout flag
        unless signatures
          log_message(
            "Inference timeout for #{gem_name}-#{version} " \
            "(#{files.size} files, parse=#{(t1 - t0).round(2)}s, " \
            "infer>#{timeout}s), deferring to on-demand"
          )
          save_unguessed_cache(gem_name, gem_info, cache, inference_timeout: true)
          return nil
        end

        # Phase C: Disk save
        cache.save(gem_name, version, deps,
                   instance_methods: signatures[:instance_methods],
                   class_methods: signatures[:class_methods])

        t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Phase D: Registry load
        @signature_registry.load_gem_cache(signatures[:instance_methods], kind: :instance)
        @signature_registry.load_gem_cache(signatures[:class_methods], kind: :class)

        t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        log_message(
          "Cached #{gem_name}-#{version} (#{files.size} files, " \
          "#{signatures[:instance_methods].size} classes) " \
          "[parse=#{(t1 - t0).round(2)}s infer=#{(t2 - t1).round(2)}s " \
          "save=#{(t3 - t2).round(2)}s load=#{(t4 - t3).round(2)}s]"
        )

        signatures
      end

      # Generate an Unguessed cache from member_index entries (no parse/infer needed).
      # Method names and parameter structure come from RubyIndexer; types are set to Unguessed.
      private def save_unguessed_cache(gem_name, gem_info, cache, inference_timeout: false)
        version = gem_info[:version]
        files = gem_info[:files]
        deps = gem_info[:transitive_deps]

        instance_methods = {}
        class_methods = {}

        files.each do |file_path|
          @code_index.member_entries_for_file(file_path).each do |entry|
            owner_name = entry.owner.name

            if owner_name.match?(/::<Class:[^>]+>\z/)
              class_name = extract_class_from_singleton(owner_name)
              target = class_methods
            else
              class_name = owner_name
              target = instance_methods
            end

            target[class_name] ||= {}
            target[class_name][entry.name] = {
              "return_type" => { "_type" => "Unguessed" },
              "params" => build_params_from_entry(entry)
            }
          end
        end

        cache.save(gem_name, version, deps,
                   instance_methods: instance_methods,
                   class_methods: class_methods,
                   fully_inferred: false,
                   inference_timeout: inference_timeout)

        @signature_registry.load_gem_cache(instance_methods, kind: :instance)
        @signature_registry.load_gem_cache(class_methods, kind: :class)

        log_message(
          "Saved unguessed cache for #{gem_name}-#{version} " \
          "(#{instance_methods.size} instance classes, #{class_methods.size} class method classes)"
        )
      end

      # Build serialized params array from a RubyIndexer::Entry::Member
      private def build_params_from_entry(entry)
        sigs = entry.signatures
        return [] if sigs.empty?

        sigs.first.parameters.filter_map do |p|
          kind = case p
                 when RubyIndexer::Entry::RequiredParameter then "required"
                 when RubyIndexer::Entry::OptionalParameter then "optional"
                 when RubyIndexer::Entry::RestParameter then "rest"
                 when RubyIndexer::Entry::KeywordParameter then "keyword_required"
                 when RubyIndexer::Entry::OptionalKeywordParameter then "keyword_optional"
                 when RubyIndexer::Entry::KeywordRestParameter then "keyword_rest"
                 when RubyIndexer::Entry::BlockParameter then "block"
                 else next
                 end
          { "name" => p.name.to_s, "kind" => kind, "type" => { "_type" => "Unguessed" } }
        end
      end

      # Fallback: index all files into main registries (no cache)
      private def index_all_files(file_paths)
        file_paths.each do |file_path|
          next unless File.exist?(file_path)

          source = File.read(file_path)
          parsed = Prism.parse(source)
          next unless parsed.value

          @mutex.synchronize do
            @location_index.remove_file(file_path)
            @method_registry.remove_file(file_path)
            @ivar_registry.remove_file(file_path)
            @cvar_registry.remove_file(file_path)

            context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
              file_path: file_path,
              location_index: @location_index,
              method_registry: @method_registry,
              ivar_registry: @ivar_registry,
              cvar_registry: @cvar_registry
            )

            parsed.value.statements&.body&.each do |stmt|
              @converter.convert(stmt, context)
            end
          end
        rescue StandardError => e
          log_message("Error indexing #{file_path}: #{e.class}: #{e.message}")
        end

        @mutex.synchronize { @location_index.finalize! }
        log_message("Indexed #{file_paths.size} files.")
      end

      # Parse and index a file into given registries (no mutex, used for temp gem registries)
      private def parse_and_index_file(file_path, converter, location_index,
                                       method_registry, ivar_registry, cvar_registry)
        return unless File.exist?(file_path)

        source = File.read(file_path)
        parsed = Prism.parse(source)
        return unless parsed.value

        context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
          file_path: file_path,
          location_index: location_index,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry
        )

        parsed.value.statements&.body&.each do |stmt|
          converter.convert(stmt, context)
        end
      rescue StandardError => e
        log_message("Error indexing gem file #{file_path}: #{e.class}: #{e.message}")
      end

      # Find Gemfile.lock in the workspace
      private def find_lockfile
        workspace_path = @global_state.workspace_path
        return nil unless workspace_path

        lockfile = File.join(workspace_path, "Gemfile.lock")
        File.exist?(lockfile) ? lockfile : nil
      end

      private def index_file_with_prism_result(file_path, prism_result)
        return unless prism_result.value

        @mutex.synchronize do
          # Clear existing index for this file
          @location_index.remove_file(file_path)
          @method_registry.remove_file(file_path)
          @ivar_registry.remove_file(file_path)
          @cvar_registry.remove_file(file_path)
          @resolver.clear_cache

          # Create context with index/registry injection - nodes are registered during conversion
          context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            ivar_registry: @ivar_registry,
            cvar_registry: @cvar_registry
          )

          prism_result.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end

          # Finalize the index for efficient lookups
          @location_index.finalize!

          # Update member_index (RubyIndexer is already updated by ruby-lsp)
          @code_index.refresh_member_index!(URI::Generic.from_path(path: file_path))
        end
      end

      # Extract simple class name from singleton format
      # "File::<Class:File>" -> "File"
      # "Namespace::MyClass::<Class:MyClass>" -> "Namespace::MyClass"
      # @param owner_class [String] Owner class name (may be singleton format)
      # @return [String] Simple class name
      private def extract_class_from_singleton(owner_class)
        # Match singleton pattern: "ClassName::<Class:ClassName>"
        if owner_class.match?(/::<Class:[^>]+>\z/)
          owner_class.sub(/::<Class:[^>]+>\z/, "")
        else
          owner_class
        end
      end

      # Background inference: fully infer gems with Unguessed entries after indexing.
      # Runs in the same indexing thread after @indexing_completed = true.
      # Replaces in-memory Unguessed entries and updates disk cache to fully_inferred.
      private def background_infer_gems(unguessed_gems, cache)
        log_message("Starting background inference for #{unguessed_gems.size} gems...")

        unguessed_gems.each do |entry|
          signatures = infer_and_cache_gem(entry[:name], entry[:info], cache)
          next unless signatures

          @signature_registry.replace_unguessed_entries(signatures[:instance_methods], kind: :instance)
          @signature_registry.replace_unguessed_entries(signatures[:class_methods], kind: :class)
        rescue StandardError => e
          log_message("Background inference failed for #{entry[:name]}: #{e.message}")
        end

        log_message("Background inference completed.")
      end

      # On-demand inference for a single gem file.
      # Triggered when SignatureRegistry encounters an Unguessed return type.
      # Parses and infers the file containing the method definition,
      # then replaces Unguessed entries with actual inferred types.
      private def infer_gem_file_on_demand(class_name, method_name, kind)
        return if @inferring_on_demand # re-entrancy guard

        singleton = kind == :class
        file_path = @code_index.method_definition_file_path(class_name, method_name, singleton: singleton)
        return unless file_path

        @inferring_on_demand = true
        begin
          temp_location_index = ::TypeGuessr::Core::Index::LocationIndex.new
          temp_method_registry = ::TypeGuessr::Core::Registry::MethodRegistry.new(code_index: @code_index)
          temp_ivar_registry = ::TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: @code_index)
          temp_cvar_registry = ::TypeGuessr::Core::Registry::ClassVariableRegistry.new

          converter = ::TypeGuessr::Core::Converter::PrismConverter.new
          parse_and_index_file(file_path, converter, temp_location_index,
                               temp_method_registry, temp_ivar_registry, temp_cvar_registry)
          temp_location_index.finalize!

          type_simplifier = ::TypeGuessr::Core::TypeSimplifier.new(code_index: @code_index)
          temp_resolver = ::TypeGuessr::Core::Inference::Resolver.new(
            @signature_registry,
            code_index: @code_index,
            method_registry: temp_method_registry,
            ivar_registry: temp_ivar_registry,
            cvar_registry: temp_cvar_registry,
            type_simplifier: type_simplifier
          )
          temp_builder = ::TypeGuessr::Core::SignatureBuilder.new(temp_resolver)
          extractor = ::TypeGuessr::Core::Cache::GemSignatureExtractor.new(
            signature_builder: temp_builder,
            method_registry: temp_method_registry,
            location_index: temp_location_index
          )

          signatures = extractor.extract([file_path])

          @signature_registry.replace_unguessed_entries(signatures[:instance_methods], kind: :instance)
          @signature_registry.replace_unguessed_entries(signatures[:class_methods], kind: :class)
        rescue StandardError => e
          log_message("On-demand inference failed for #{class_name}##{method_name}: #{e.message}")
        ensure
          @inferring_on_demand = false
        end
      end

      # Poll index entry count until it stops growing for stable_threshold consecutive checks.
      # Other addons (ruby-lsp-rails, etc.) may register entries after initial_indexing_completed.
      private def wait_for_index_stabilization(index, interval: 1, stable_threshold: 3)
        previous_count = index.length
        stable_ticks = 0

        loop do
          sleep(interval)
          current_count = index.length

          if current_count == previous_count
            stable_ticks += 1
            break if stable_ticks >= stable_threshold
          else
            log_message("Index still growing: #{current_count} entries (+#{current_count - previous_count})")
            stable_ticks = 0
            previous_count = current_count
          end
        end

        log_message("Index stabilized at #{previous_count} entries.")
      end

      private def log_message(message)
        return unless @message_queue
        return if @message_queue.closed?

        @message_queue << RubyLsp::Notification.window_log_message(
          "[TypeGuessr] #{message}",
          type: RubyLsp::Constant::MessageType::LOG
        )
      end
    end
  end
end
