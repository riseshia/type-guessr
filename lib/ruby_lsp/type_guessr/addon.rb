# frozen_string_literal: true

require "ruby_lsp/addon"
require "prism"
require_relative "hover"

# Explicitly require core dependencies used by this addon
require_relative "../../type_guessr/version" unless defined?(TypeGuessr::VERSION)
require_relative "../../type_guessr/core/ast_analyzer"
require_relative "../../type_guessr/core/rbs_indexer"
require_relative "../../type_guessr/core/variable_index"
require_relative "../../type_guessr/core/method_signature_index"

module RubyLsp
  module TypeGuessr
    # Ruby LSP addon for TypeGuessr
    # Provides hover tooltip functionality for Ruby code
    class Addon < ::RubyLsp::Addon
      def name
        "TypeGuessr"
      end

      def version
        ::TypeGuessr::VERSION
      end

      def activate(global_state, message_queue)
        @global_state = global_state
        @message_queue = message_queue

        log_message("Activating TypeGuessr LSP addon #{::TypeGuessr::VERSION}.")

        # Extend Ruby LSP's ALLOWED_TARGETS to support local variables, parameters, and self for hover
        targets = RubyLsp::Listeners::Hover::ALLOWED_TARGETS

        # Only add if not already present (to handle multiple activations in tests)
        new_targets = [
          Prism::LocalVariableReadNode,
          Prism::LocalVariableWriteNode,
          Prism::LocalVariableTargetNode,
          Prism::RequiredParameterNode,
          Prism::OptionalParameterNode,
          Prism::RestParameterNode,
          Prism::RequiredKeywordParameterNode,
          Prism::OptionalKeywordParameterNode,
          Prism::KeywordRestParameterNode,
          Prism::BlockParameterNode,
          Prism::ForwardingParameterNode,
          Prism::SelfNode
        ]

        new_targets.each do |target|
          targets << target unless targets.include?(target)
        end

        # Start background thread to index RBS signatures
        start_rbs_indexing

        # Start background thread to traverse AST for indexed files
        start_ast_traversal(global_state)
      end

      def deactivate
        # Deactivation logic if needed
      end

      # Handle file change notifications from LSP client
      # Re-index files when they are created, updated, or deleted
      def workspace_did_change_watched_files(changes)
        changes.each do |change|
          uri = URI(change[:uri])
          file_path = uri.to_standardized_path
          next if file_path.nil? || File.directory?(file_path)
          next unless file_path.end_with?(".rb")

          case change[:type]
          when Constant::FileChangeType::CREATED, Constant::FileChangeType::CHANGED
            # Re-index the file by traversing its AST
            reindex_file(file_path)
          when Constant::FileChangeType::DELETED
            # Clear index entries for the deleted file
            clear_file_index(file_path)
          end
        rescue StandardError => e
          log_message("Error processing file change #{uri}: #{e.message}")
        end
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        Hover.new(response_builder, node_context, dispatcher, @global_state)
      end

      private

      # Send a log message to the LSP client
      def log_message(message)
        return unless @message_queue
        return if @message_queue.closed?

        @message_queue << RubyLsp::Notification.window_log_message(
          "[TypeGuessr] #{message}",
          type: RubyLsp::Constant::MessageType::LOG
        )
      end

      def start_rbs_indexing
        Thread.new do
          log_message("Starting RBS signature indexing.")
          indexer = ::TypeGuessr::Core::RBSIndexer.new

          # Index Ruby core library
          log_message("Indexing Ruby core library signatures...")
          indexer.index_ruby_core

          # Index project RBS files from sig/ directory
          log_message("Indexing project RBS signatures...")
          indexer.index_project_rbs

          total_signatures = ::TypeGuessr::Core::MethodSignatureIndex.instance.size
          log_message("RBS indexing completed. Total signatures: #{total_signatures}")
        rescue StandardError => e
          log_message("Error during RBS indexing: #{e.message}")
          log_message(e.backtrace.join("\n"))
        end
      end

      def start_ast_traversal(global_state)
        Thread.new do
          log_message("Starting AST traversal with parallel processing.")
          index = global_state.index

          # Get indexable URIs from RubyIndexer configuration
          indexable_uris = index.configuration.indexable_uris
          log_message("Found #{indexable_uris.size} indexed files to traverse.")

          # Use 8 worker threads for parallel processing
          worker_count = 8
          log_message("Using #{worker_count} worker threads.")

          # Thread-safe progress tracking
          progress_mutex = Mutex.new
          processed_count = 0
          progress_step = (indexable_uris.size / 10.0).ceil

          # Create a thread pool with work queue
          queue = Thread::Queue.new
          indexable_uris.each { |uri| queue << uri }
          worker_count.times { queue << :stop } # Sentinel values to stop workers

          # Start worker threads
          workers = worker_count.times.map do
            Thread.new do
              loop do
                uri = queue.pop
                break if uri == :stop

                begin
                  traverse_file_ast(uri)

                  # Update progress in thread-safe manner
                  progress_mutex.synchronize do
                    processed_count += 1

                    # Log progress every 10%
                    if progress_step.positive? && (processed_count % progress_step).zero?
                      progress = (processed_count / progress_step.to_f * 10).to_i
                      log_message("Progress: #{progress}% (#{processed_count}/#{indexable_uris.size} files)")
                    end
                  end
                rescue StandardError => e
                  log_message("Error processing #{uri}: #{e.message}")
                end
              end
            end
          end

          # Wait for all workers to complete
          workers.each(&:join)

          log_message("AST traversal completed. Processed #{processed_count} files.")
        rescue StandardError => e
          log_message("Error during AST traversal: #{e.message}")
          log_message(e.backtrace.join("\n"))
        end
      end

      def traverse_file_ast(uri)
        file_path = uri.full_path
        return unless file_path && File.exist?(file_path)

        source = File.read(file_path)
        result = Prism.parse(source)

        # Use a visitor to traverse the AST
        visitor = ::TypeGuessr::Core::ASTAnalyzer.new(file_path)
        result.value.accept(visitor)
      rescue StandardError => e
        log_message("Error parsing #{uri}: #{e.message}")
      end

      # Re-index a single file by traversing its AST
      def reindex_file(file_path)
        return unless File.exist?(file_path)

        # First, clear existing index entries for this file
        clear_file_index(file_path)

        # Then, re-traverse the file's AST
        source = File.read(file_path)
        result = Prism.parse(source)

        visitor = ::TypeGuessr::Core::ASTAnalyzer.new(file_path)
        result.value.accept(visitor)

        log_message("Re-indexed file: #{file_path}")
      rescue StandardError => e
        log_message("Error re-indexing #{file_path}: #{e.message}")
      end

      # Clear all index entries for a specific file
      def clear_file_index(file_path)
        ::TypeGuessr::Core::VariableIndex.instance.clear_file(file_path)
        log_message("Cleared index for file: #{file_path}")
      rescue StandardError => e
        log_message("Error clearing index for #{file_path}: #{e.message}")
      end
    end
  end
end
