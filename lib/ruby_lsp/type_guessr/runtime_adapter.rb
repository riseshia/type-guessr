# frozen_string_literal: true

require "prism"
require_relative "../../type_guessr/core/converter/prism_converter"
require_relative "../../type_guessr/core/index/location_index"
require_relative "../../type_guessr/core/inference/resolver"
require_relative "../../type_guessr/core/signature_provider"
require_relative "../../type_guessr/core/rbs_provider"
require_relative "type_inferrer"

module RubyLsp
  module TypeGuessr
    # RuntimeAdapter manages the IR graph and inference for TypeGuessr
    # Converts files to IR graphs and provides type inference
    class RuntimeAdapter
      attr_reader :signature_provider

      def initialize(global_state, message_queue = nil)
        @global_state = global_state
        @message_queue = message_queue
        @converter = ::TypeGuessr::Core::Converter::PrismConverter.new
        @location_index = ::TypeGuessr::Core::Index::LocationIndex.new
        @signature_provider = build_signature_provider
        @resolver = ::TypeGuessr::Core::Inference::Resolver.new(@signature_provider)
        @indexing_completed = false
        @mutex = Mutex.new
        @original_type_inferrer = nil

        # Set up duck type resolver callback
        @resolver.duck_type_resolver = ->(duck_type) { resolve_duck_type_to_class(duck_type) }
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
          result = @resolver.infer(node)

          # Post-process DuckType to resolve to actual classes
          if result.type.is_a?(::TypeGuessr::Core::Types::DuckType)
            resolve_duck_type(result)
          else
            result
          end
        end
      end

      # Resolve DuckType to ClassInstance(s) by looking up classes that define all methods
      def resolve_duck_type(result)
        duck_type = result.type
        methods = duck_type.methods

        # First try project methods (registered during indexing)
        project_resolved = @resolver.send(:resolve_duck_type_from_project_methods, duck_type)
        if project_resolved
          return ::TypeGuessr::Core::Inference::Result.new(
            project_resolved,
            "inferred from method calls: #{methods.join(", ")} (project)",
            :project
          )
        end

        # Then try RubyIndexer for stdlib/gem classes
        matching_classes = find_classes_defining_methods(methods)

        case matching_classes.size
        when 0
          # No matching classes, keep the DuckType
          result
        when 1
          # Exactly one class matches - return ClassInstance
          ::TypeGuessr::Core::Inference::Result.new(
            ::TypeGuessr::Core::Types::ClassInstance.new(matching_classes.first),
            "inferred from method calls: #{methods.join(", ")}",
            :inference
          )
        when 2, 3
          # 2-3 matches - return union of classes
          types = matching_classes.map { |c| ::TypeGuessr::Core::Types::ClassInstance.new(c) }
          ::TypeGuessr::Core::Inference::Result.new(
            ::TypeGuessr::Core::Types::Union.new(types),
            "ambiguous: #{matching_classes.join(" | ")} from method calls",
            :inference
          )
        else
          # 4+ matches - return untyped (too ambiguous)
          ::TypeGuessr::Core::Inference::Result.new(
            ::TypeGuessr::Core::Types::Unknown.instance,
            "too many matching types for method calls",
            :unknown
          )
        end
      end

      # Resolve DuckType to a type (for use during inference)
      # Returns the resolved type or nil if not resolvable
      def resolve_duck_type_to_class(duck_type)
        methods = duck_type.methods
        matching_classes = find_classes_defining_methods(methods)

        case matching_classes.size
        when 0
          nil # Keep as DuckType
        when 1
          ::TypeGuessr::Core::Types::ClassInstance.new(matching_classes.first)
        when 2, 3
          types = matching_classes.map { |c| ::TypeGuessr::Core::Types::ClassInstance.new(c) }
          ::TypeGuessr::Core::Types::Union.new(types)
          # 4+ matches → nil (too ambiguous), case returns nil by default
        end
      end

      # Find classes that define all given methods
      def find_classes_defining_methods(methods)
        return [] if methods.empty?

        index = @global_state.index
        return [] unless index

        # For each method, find classes that define it using fuzzy_search
        method_sets = methods.map do |method_name|
          entries = index.fuzzy_search(method_name.to_s) do |entry|
            entry.is_a?(RubyIndexer::Entry::Method) && entry.name == method_name.to_s
          end
          entries.filter_map do |entry|
            entry.owner.name if entry.respond_to?(:owner) && entry.owner
          end.uniq
        end

        return [] if method_sets.empty? || method_sets.any?(&:empty?)

        # Find intersection - classes that define ALL methods
        method_sets.reduce(:&) || []
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

      # Get all registered class names (thread-safe)
      # @return [Array<String>] List of class names
      def registered_classes
        @mutex.synchronize { @resolver.registered_classes }
      end

      # Get all methods for a specific class (thread-safe)
      # @param class_name [String] Class name
      # @return [Hash<String, DefNode>] Methods hash
      def methods_for_class(class_name)
        @mutex.synchronize { @resolver.methods_for_class(class_name) }
      end

      # Search for methods matching a pattern (thread-safe)
      # @param query [String] Search query (e.g., "User#save" or "save")
      # @return [Array<Hash>] Array of method info hashes
      def search_project_methods(query)
        @mutex.synchronize do
          @resolver.search_methods(query).map do |class_name, method_name, def_node|
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
        file_path = uri.full_path.to_s # Ensure string
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

        # Add the node itself with current scope
        @location_index.add(file_path, node, scope_id)

        # Recursively add children based on node type, updating scope as needed
        case node
        when ::TypeGuessr::Core::IR::ClassModuleNode
          # Enter class/module scope (concatenate with parent scope)
          new_scope = scope_id.empty? ? node.name : "#{scope_id}::#{node.name}"
          # Index all methods and nested classes in the class/module
          node.methods&.each do |method|
            if method.is_a?(::TypeGuessr::Core::IR::ClassModuleNode)
              # Recursively index nested class/module with concatenated scope
              index_node_recursively(file_path, method, scope_id.empty? ? node.name : "#{scope_id}::#{node.name}")
            else
              # Regular method
              index_node_recursively(file_path, method, new_scope)
              # Register method for project method lookup (use full scope for correct key lookup)
              @resolver.register_method(new_scope, method.name.to_s, method)
            end
          end

        when ::TypeGuessr::Core::IR::DefNode
          # Enter method scope
          new_scope = scope_id.empty? ? "##{node.name}" : "#{scope_id}##{node.name}"
          # Index parameters
          node.params&.each { |param| index_node_recursively(file_path, param, new_scope) }
          # Index all body nodes (including intermediate statements)
          node.body_nodes&.each { |body_node| index_node_recursively(file_path, body_node, new_scope) }

        when ::TypeGuessr::Core::IR::LocalWriteNode
          # Index value
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::LocalReadNode
          # No recursive indexing needed (write_node is already indexed)
          nil

        when ::TypeGuessr::Core::IR::InstanceVariableWriteNode
          # Register with resolver for deferred lookup
          @resolver.register_instance_variable(node.class_name, node.name, node) if node.class_name
          # Index value
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::InstanceVariableReadNode
          # No recursive indexing needed (deferred lookup at inference time)
          nil

        when ::TypeGuessr::Core::IR::ClassVariableWriteNode
          # Register with resolver for deferred lookup
          @resolver.register_class_variable(node.class_name, node.name, node) if node.class_name
          # Index value
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::ClassVariableReadNode
          # No recursive indexing needed (deferred lookup at inference time)
          nil

        when ::TypeGuessr::Core::IR::CallNode
          # Index receiver
          index_node_recursively(file_path, node.receiver, scope_id) if node.receiver
          # Index arguments
          node.args&.each { |arg| index_node_recursively(file_path, arg, scope_id) }
          # Index block params
          node.block_params&.each { |param| index_node_recursively(file_path, param, scope_id) }
          # Index block body
          index_node_recursively(file_path, node.block_body, scope_id) if node.block_body

        when ::TypeGuessr::Core::IR::ParamNode
          # Index default value
          index_node_recursively(file_path, node.default_value, scope_id) if node.default_value

        when ::TypeGuessr::Core::IR::MergeNode
          # Index branches
          node.branches&.each { |branch| index_node_recursively(file_path, branch, scope_id) }

        when ::TypeGuessr::Core::IR::ReturnNode
          # Index return value
          index_node_recursively(file_path, node.value, scope_id) if node.value

        when ::TypeGuessr::Core::IR::ConstantNode
          # Index dependency
          index_node_recursively(file_path, node.dependency, scope_id) if node.dependency
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
