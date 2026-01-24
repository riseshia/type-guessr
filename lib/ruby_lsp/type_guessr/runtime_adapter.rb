# frozen_string_literal: true

require "prism"
require_relative "../../type_guessr/core/converter/prism_converter"
require_relative "../../type_guessr/core/index/location_index"
require_relative "../../type_guessr/core/registry/method_registry"
require_relative "../../type_guessr/core/registry/variable_registry"
require_relative "../../type_guessr/core/inference/resolver"
require_relative "../../type_guessr/core/signature_provider"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "../../type_guessr/core/type_simplifier"
require_relative "code_index_adapter"
require_relative "type_inferrer"

module RubyLsp
  module TypeGuessr
    # RuntimeAdapter manages the IR graph and inference for TypeGuessr
    # Converts files to IR graphs and provides type inference
    class RuntimeAdapter
      attr_reader :signature_provider, :location_index, :resolver, :method_registry

      def initialize(global_state, message_queue = nil)
        @global_state = global_state
        @message_queue = message_queue
        @converter = ::TypeGuessr::Core::Converter::PrismConverter.new
        @location_index = ::TypeGuessr::Core::Index::LocationIndex.new
        @signature_provider = build_signature_provider
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

        # Create resolver with code_index adapter and registries
        @resolver = ::TypeGuessr::Core::Inference::Resolver.new(
          @signature_provider,
          code_index: @code_index,
          method_registry: @method_registry,
          variable_registry: @variable_registry
        )

        # Set up type simplifier with code_index for inheritance lookup
        @resolver.type_simplifier = ::TypeGuessr::Core::TypeSimplifier.new(
          code_index: @code_index
        )
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

        # Parse and convert to IR outside mutex
        parsed = document.parse_result
        return unless parsed.value

        # Create a shared context for all statements
        context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new
        nodes = parsed.value.statements&.body&.filter_map do |stmt|
          @converter.convert(stmt, context)
        end

        @mutex.synchronize do
          # Clear existing index for this file
          @location_index.remove_file(file_path)
          @resolver.clear_cache

          # Index all nodes recursively with scope tracking
          nodes&.each { |node| index_node_recursively(file_path, node, "") }

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

          # Create a shared context for all statements
          context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new

          # Convert statements to IR nodes and index with scope tracking
          parsed.value.statements&.body&.each do |stmt|
            node = @converter.convert(stmt, context)
            index_node_recursively(file_path, node, "") if node
          end

          # Finalize the index for efficient lookups
          @location_index.finalize!
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

      private

      # Traverse and index a single file
      def traverse_file(uri)
        file_path = uri.to_standardized_path
        return unless file_path && File.exist?(file_path)

        # Parse outside mutex (CPU-bound, no shared state)
        source = File.read(file_path)
        parsed = Prism.parse(source)
        return unless parsed.value

        # Create context and convert nodes outside mutex
        context = ::TypeGuessr::Core::Converter::PrismConverter::Context.new
        nodes = parsed.value.statements&.body&.filter_map do |stmt|
          @converter.convert(stmt, context)
        end

        # Only hold mutex while modifying shared state
        @mutex.synchronize do
          @location_index.remove_file(file_path)
          nodes&.each { |node| index_node_recursively(file_path, node, "") }
        end
        # NOTE: finalize! is called once after ALL files are indexed in start_indexing
      rescue StandardError => e
        bt = e.backtrace&.first(5)&.join("\n") || "(no backtrace)"
        log_message("Error indexing #{uri}: #{e.class}: #{e.message}\n#{bt}")
      end

      # Recursively index a node and all its children with scope tracking
      # @param file_path [String] Absolute file path
      # @param node [TypeGuessr::Core::IR::Node] IR node to index
      # @param scope_id [String] Current scope identifier (e.g., "User#save")
      def index_node_recursively(file_path, node, scope_id)
        return unless node

        case node
        when ::TypeGuessr::Core::IR::DefNode
          index_def_node(file_path, node, scope_id)

        when ::TypeGuessr::Core::IR::ClassModuleNode
          index_class_module_node(file_path, node, scope_id)

        when ::TypeGuessr::Core::IR::CallNode
          @location_index.add(file_path, node, scope_id)
          index_node_recursively(file_path, node.receiver, scope_id) if node.receiver
          node.args&.each { |arg| index_node_recursively(file_path, arg, scope_id) }
          node.block_params&.each { |param| index_node_recursively(file_path, param, scope_id) }
          index_node_recursively(file_path, node.block_body, scope_id) if node.block_body

        when ::TypeGuessr::Core::IR::MergeNode
          @location_index.add(file_path, node, scope_id)
          node.branches&.each { |branch| index_node_recursively(file_path, branch, scope_id) }

        when ::TypeGuessr::Core::IR::InstanceVariableWriteNode
          @location_index.add(file_path, node, scope_id)
          @variable_registry.register_instance_variable(node.class_name, node.name, node) if node.class_name
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::ClassVariableWriteNode
          @location_index.add(file_path, node, scope_id)
          @variable_registry.register_class_variable(node.class_name, node.name, node) if node.class_name
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::LocalWriteNode
          @location_index.add(file_path, node, scope_id)
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::ParamNode
          @location_index.add(file_path, node, scope_id)
          index_node_recursively(file_path, node.default_value, scope_id) if node.default_value

        when ::TypeGuessr::Core::IR::ReturnNode
          @location_index.add(file_path, node, scope_id)
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::ConstantNode
          @location_index.add(file_path, node, scope_id)
          index_node_recursively(file_path, node.dependency, scope_id) if node.dependency

        when ::TypeGuessr::Core::IR::LiteralNode
          @location_index.add(file_path, node, scope_id)
          # Index value nodes (e.g., variable references in arrays/hashes/keyword args)
          node.values&.each { |value| index_node_recursively(file_path, value, scope_id) }

        else
          # LocalReadNode, InstanceVariableReadNode, ClassVariableReadNode, etc.
          @location_index.add(file_path, node, scope_id)
        end
      end

      def index_def_node(file_path, node, scope_id)
        method_scope = singleton_scope_for(scope_id, singleton: node.singleton)
        @location_index.add(file_path, node, method_scope)

        new_scope = method_scope.empty? ? "##{node.name}" : "#{method_scope}##{node.name}"
        @method_registry.register("", node.name.to_s, node) if scope_id.empty?

        node.params&.each { |param| index_node_recursively(file_path, param, new_scope) }
        node.body_nodes&.each { |body_node| index_node_recursively(file_path, body_node, new_scope) }
      end

      def index_class_module_node(file_path, node, scope_id)
        @location_index.add(file_path, node, scope_id)

        new_scope = scope_id.empty? ? node.name : "#{scope_id}::#{node.name}"

        node.methods&.each do |method|
          if method.is_a?(::TypeGuessr::Core::IR::ClassModuleNode)
            index_node_recursively(file_path, method, new_scope)
          else
            index_node_recursively(file_path, method, new_scope)

            method_scope = singleton_scope_for(new_scope, singleton: method.singleton)
            @method_registry.register(method_scope, method.name.to_s, method)
          end
        end
      end

      # Build SignatureProvider with configured type sources
      # Currently uses RBSProvider for stdlib types
      # Can be extended to add project RBS, Sorbet, etc.
      def build_signature_provider
        provider = ::TypeGuessr::Core::SignatureProvider.new

        # Add stdlib RBS provider (lowest priority)
        provider.add_provider(::TypeGuessr::Core::RBSProvider.instance)

        # Future: Add project RBS provider (high priority)
        # provider.add_provider(ProjectRBSProvider.new, priority: :high)

        provider
      end

      # Build singleton class scope for method registration/lookup
      # Singleton methods use "<Class:ClassName>" suffix to match RubyIndexer convention
      # @param scope [String] Base scope (e.g., "RBS::Environment2")
      # @param singleton [Boolean] Whether the method is a singleton method
      # @return [String] Scope with singleton class suffix if applicable
      def singleton_scope_for(scope, singleton:)
        return scope unless singleton

        parent_name = scope.split("::").last || "Object"
        scope.empty? ? "<Class:Object>" : "#{scope}::<Class:#{parent_name}>"
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
