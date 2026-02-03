# frozen_string_literal: true

require "prism"
require_relative "../../type_guessr/core/converter/prism_converter"
require_relative "../../type_guessr/core/index/location_index"
require_relative "../../type_guessr/core/registry/method_registry"
require_relative "../../type_guessr/core/registry/variable_registry"
require_relative "../../type_guessr/core/registry/signature_registry"
require_relative "../../type_guessr/core/inference/resolver"
require_relative "../../type_guessr/core/signature_builder"
require_relative "../../type_guessr/core/type_simplifier"
require_relative "../../type_guessr/core/node_context_helper"
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

        # Create variable registry with code_index for inheritance lookup
        @variable_registry = ::TypeGuessr::Core::Registry::VariableRegistry.new(
          code_index: @code_index
        )

        # Create type simplifier with code_index for inheritance lookup
        type_simplifier = ::TypeGuessr::Core::TypeSimplifier.new(
          code_index: @code_index
        )

        # Create resolver with signature_registry and registries
        @resolver = ::TypeGuessr::Core::Inference::Resolver.new(
          @signature_registry,
          code_index: @code_index,
          method_registry: @method_registry,
          variable_registry: @variable_registry,
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
        return unless parsed.value

        @mutex.synchronize do
          # Clear existing index for this file
          @location_index.remove_file(file_path)
          @resolver.clear_cache

          # Create context with index/registry injection - nodes are registered during conversion
          context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            variable_registry: @variable_registry
          )

          parsed.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end

          # Finalize the index for efficient lookups
          @location_index.finalize!
        end
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

        @mutex.synchronize do
          # Clear existing index for this file
          @location_index.remove_file(file_path)
          @resolver.clear_cache

          # Parse source code
          parsed = Prism.parse(source)
          return unless parsed.value

          # Create context with index/registry injection - nodes are registered during conversion
          context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            variable_registry: @variable_registry
          )

          parsed.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end

          # Finalize the index for efficient lookups
          @location_index.finalize!
        end
      end

      # Remove indexed data for a file
      # @param file_path [String] File path to remove
      def remove_indexed_file(file_path)
        @mutex.synchronize do
          @location_index.remove_file(file_path)
          @resolver.clear_cache
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
          log_message("Ruby LSP indexing completed. Starting TypeGuessr file indexing.")

          # Get all indexable files (project + gems)
          indexable_uris = index.configuration.indexable_uris
          total = indexable_uris.size
          log_message("Found #{total} files to process.")

          # Index each file with progress reporting
          processed = 0
          last_report = 0
          report_interval = [total / 10, 50].max

          indexable_uris.each do |uri|
            traverse_file(uri)
            processed += 1

            next unless processed - last_report >= report_interval

            percent = (processed * 100.0 / total).round(1)
            log_message("Indexing progress: #{processed}/#{total} (#{percent}%)")
            last_report = processed
          end

          # Finalize the index ONCE after all files are processed
          @mutex.synchronize { @location_index.finalize! }

          log_message("File indexing completed. Processed #{total} files.")
          @signature_registry.preload
          @indexing_completed = true
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

      private

      # Extract simple class name from singleton format
      # "File::<Class:File>" -> "File"
      # "Namespace::MyClass::<Class:MyClass>" -> "Namespace::MyClass"
      # @param owner_class [String] Owner class name (may be singleton format)
      # @return [String] Simple class name
      def extract_class_from_singleton(owner_class)
        # Match singleton pattern: "ClassName::<Class:ClassName>"
        if owner_class.match?(/::<Class:[^>]+>\z/)
          owner_class.sub(/::<Class:[^>]+>\z/, "")
        else
          owner_class
        end
      end

      # Traverse and index a single file
      def traverse_file(uri)
        file_path = uri.to_standardized_path
        return unless file_path && File.exist?(file_path)

        # Parse outside mutex (CPU-bound, no shared state)
        source = File.read(file_path)
        parsed = Prism.parse(source)
        return unless parsed.value

        # Only hold mutex while modifying shared state
        @mutex.synchronize do
          @location_index.remove_file(file_path)

          # Create context with index/registry injection - nodes are registered during conversion
          context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new(
            file_path: file_path,
            location_index: @location_index,
            method_registry: @method_registry,
            variable_registry: @variable_registry
          )

          parsed.value.statements&.body&.each do |stmt|
            @converter.convert(stmt, context)
          end
        end
        # NOTE: finalize! is called once after ALL files are indexed in start_indexing
      rescue StandardError => e
        bt = e.backtrace&.first(5)&.join("\n") || "(no backtrace)"
        log_message("Error indexing #{uri}: #{e.class}: #{e.message}\n#{bt}")
      end

      def log_message(message)
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
