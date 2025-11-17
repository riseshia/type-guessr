# frozen_string_literal: true

require "ruby_lsp/addon"
require "prism"
require_relative "hover"

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

      def activate(global_state, _message_queue)
        warn("[TypeGuessr] Activating TypeGuessr LSP addon #{::TypeGuessr::VERSION}.")

        @global_state = global_state

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
          warn("[TypeGuessr] Error processing file change #{uri}: #{e.message}")
        end
      end

      def create_hover_listener(response_builder, node_context, dispatcher)
        Hover.new(response_builder, node_context, dispatcher, @global_state)
      end

      private

      def start_rbs_indexing
        Thread.new do
          warn("[TypeGuessr] Starting RBS signature indexing.")
          indexer = ::TypeGuessr::Core::RBSIndexer.new

          # Index Ruby core library
          warn("[TypeGuessr] Indexing Ruby core library signatures...")
          indexer.index_ruby_core

          # Index project RBS files from sig/ directory
          warn("[TypeGuessr] Indexing project RBS signatures...")
          indexer.index_project_rbs

          total_signatures = ::TypeGuessr::Core::MethodSignatureIndex.instance.size
          warn("[TypeGuessr] RBS indexing completed. Total signatures: #{total_signatures}")
        rescue StandardError => e
          warn("[TypeGuessr] Error during RBS indexing: #{e.message}")
          warn(e.backtrace.join("\n"))
        end
      end

      def start_ast_traversal(global_state)
        Thread.new do
          warn("[TypeGuessr] Starting AST traversal with parallel processing.")
          index = global_state.index

          # Get indexable URIs from RubyIndexer configuration
          indexable_uris = index.configuration.indexable_uris
          warn("[TypeGuessr] Found #{indexable_uris.size} indexed files to traverse.")

          # Use 8 worker threads for parallel processing
          worker_count = 8
          warn("[TypeGuessr] Using #{worker_count} worker threads.")

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
                      warn("[TypeGuessr] Progress: #{progress}% (#{processed_count}/#{indexable_uris.size} files)")
                    end
                  end
                rescue StandardError => e
                  warn("[TypeGuessr] Error processing #{uri}: #{e.message}")
                end
              end
            end
          end

          # Wait for all workers to complete
          workers.each(&:join)

          warn("[TypeGuessr] AST traversal completed. Processed #{processed_count} files.")
        rescue StandardError => e
          warn("[TypeGuessr] Error during AST traversal: #{e.message}")
          warn(e.backtrace.join("\n"))
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
        warn("[TypeGuessr] Error parsing #{uri}: #{e.message}")
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

        warn("[TypeGuessr] Re-indexed file: #{file_path}")
      rescue StandardError => e
        warn("[TypeGuessr] Error re-indexing #{file_path}: #{e.message}")
      end

      # Clear all index entries for a specific file
      def clear_file_index(file_path)
        ::TypeGuessr::Core::VariableIndex.instance.clear_file(file_path)
        warn("[TypeGuessr] Cleared index for file: #{file_path}")
      rescue StandardError => e
        warn("[TypeGuessr] Error clearing index for #{file_path}: #{e.message}")
      end
    end
  end
end
