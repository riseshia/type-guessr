# frozen_string_literal: true

module TypeGuessr
  module MCP
    # Standalone runtime that mirrors RuntimeAdapter's query interface
    # without depending on ruby-lsp's GlobalState.
    #
    # Provides type inference, method signature lookup, and method search
    # for use by the MCP server. All public query methods are thread-safe.
    class StandaloneRuntime
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
          @method_registry.remove_file(file_path)
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
          @method_registry.remove_file(file_path)
          @resolver.clear_cache
        end
      end

      # Delegate member_index build to code_index
      def build_member_index!
        @code_index.build_member_index!
      end

      # Delegate member_index refresh to code_index
      # @param file_uri [URI::Generic] File URI
      def refresh_member_index!(file_uri)
        @code_index.refresh_member_index!(file_uri)
      end

      # Finalize location index after all files are indexed
      def finalize_index!
        @mutex.synchronize { @location_index.finalize! }
      end

      # Preload RBS signatures for inference
      def preload_signatures!
        @signature_registry.preload
      end

      # Get method signature for a class#method
      # @param class_name [String] Fully qualified class name (e.g., "User", "Admin::User")
      # @param method_name [String] Method name (e.g., "save", "initialize")
      # @return [Hash] Signature result with :source and :signature keys, or :error on failure
      def method_signature(class_name, method_name)
        def_node = @mutex.synchronize { @method_registry.lookup(class_name, method_name) }

        unless def_node
          entry = @signature_registry.lookup(class_name, method_name)

          if entry.is_a?(Core::Registry::SignatureRegistry::MethodEntry)
            return {
              source: "rbs",
              signatures: entry.signature_strings,
              class_name: class_name,
              method_name: method_name
            }
          end

          if entry.is_a?(Core::Registry::SignatureRegistry::GemMethodEntry)
            return {
              source: "gem_cache",
              signatures: entry.signature_strings,
              class_name: class_name,
              method_name: method_name
            }
          end

          return { error: "Method not found: #{class_name}##{method_name}", class_name: class_name,
                   method_name: method_name }
        end

        sig = @mutex.synchronize { @signature_builder.build_from_def_node(def_node) }
        {
          source: "project",
          signature: sig.to_s,
          class_name: class_name,
          method_name: method_name
        }
      rescue StandardError => e
        { error: e.message, class_name: class_name, method_name: method_name }
      end

      # Get signatures for multiple methods in one call
      # @param methods [Array<Hash>] Array of { class_name:, method_name: } hashes
      # @return [Array<Hash>] Array of signature results (same format as method_signature)
      def method_signatures(methods)
        methods.map do |entry|
          method_signature(entry[:class_name], entry[:method_name])
        end
      end

      # Get source code for a single method
      # @param class_name [String] Fully qualified class name
      # @param method_name [String] Method name
      # @return [Hash] Source result with :source, :file_path, :line keys, or :error on failure
      def method_source(class_name, method_name)
        def_node = @mutex.synchronize { @method_registry.lookup(class_name, method_name) }
        unless def_node
          return { error: "Method not found: #{class_name}##{method_name}",
                   class_name: class_name, method_name: method_name }
        end

        file_path = @mutex.synchronize { @method_registry.source_file_for(class_name, method_name) }
        unless file_path
          return { error: "Source file not found: #{class_name}##{method_name}",
                   class_name: class_name, method_name: method_name }
        end

        source = File.read(file_path)
        prism_result = Prism.parse(source)
        node_context = RubyLsp::RubyDocument.locate(
          prism_result.value, def_node.loc,
          code_units_cache: prism_result.code_units_cache(Encoding::UTF_8)
        )
        prism_def = node_context.node.is_a?(Prism::DefNode) ? node_context.node : node_context.parent

        {
          class_name: class_name,
          method_name: method_name,
          source: prism_def.slice,
          file_path: file_path,
          line: prism_def.location.start_line
        }
      rescue StandardError => e
        { error: e.message, class_name: class_name, method_name: method_name }
      end

      # Get source code for multiple methods in one call
      # @param methods [Array<Hash>] Array of { class_name:, method_name: } hashes
      # @return [Array<Hash>] Array of source results (same format as method_source)
      def method_sources(methods)
        methods.map do |entry|
          method_source(entry[:class_name], entry[:method_name])
        end
      end

      # Search for methods matching a query pattern
      # @param query [String] Search query (e.g., "User#save", "save", "initialize")
      # @param include_signatures [Boolean] When true, include inferred signature for each result
      # @return [Array<Hash>] Array of matching methods with :class_name, :method_name, :full_name, :location
      def search_methods(query, include_signatures: false)
        @mutex.synchronize do
          results = @method_registry.search(query)
          results.map do |class_name, method_name, def_node|
            entry = {
              class_name: class_name,
              method_name: method_name,
              full_name: "#{class_name}##{method_name}",
              location: def_node.loc ? { offset: def_node.loc } : nil
            }
            if include_signatures
              sig = @signature_builder.build_from_def_node(def_node)
              entry[:signature] = sig.to_s
            end
            entry
          end
        end
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
