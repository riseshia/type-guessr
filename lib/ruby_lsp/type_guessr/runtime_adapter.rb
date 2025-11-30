# frozen_string_literal: true

require "prism"

require_relative "../../type_guessr/version" if !defined?(TypeGuessr::VERSION)
require_relative "../../type_guessr/core/ast_analyzer"
require_relative "../../type_guessr/core/variable_index"
require_relative "type_inferrer"

module RubyLsp
  module TypeGuessr
    # Provides runtime functionality for TypeGuessr LSP addon.
    # Handles AST traversal, indexing, and type inferrer management.
    # @api private
    class RuntimeAdapter
      # Number of worker threads for parallel AST analysis
      WORKER_COUNT = 4

      def initialize(global_state, message_queue)
        @global_state = global_state
        @message_queue = message_queue
        @original_type_inferrer = nil
      end

      # Swap the ruby-lsp's type inferrer with our custom implementation
      def swap_type_inferrer
        @original_type_inferrer = @global_state.type_inferrer
        custom_inferrer = ::RubyLsp::TypeGuessr::TypeInferrer.new(@global_state.index)
        @global_state.instance_variable_set(:@type_inferrer, custom_inferrer)
        log_message("Swapped TypeInferrer with RubyLsp::TypeGuessr::TypeInferrer")
      end

      # Restore the original type inferrer
      def restore_type_inferrer
        return if !@global_state || !@original_type_inferrer

        @global_state.instance_variable_set(:@type_inferrer, @original_type_inferrer)
        log_message("Restored original TypeInferrer")
      end

      # Start background thread to traverse AST for indexed files
      # Waits for Ruby LSP's initial indexing to complete before starting
      def start_ast_traversal
        Thread.new do
          index = @global_state.index

          # Wait for Ruby LSP's initial indexing to complete
          log_message("Waiting for Ruby LSP initial indexing to complete...")
          sleep(0.1) until index.initial_indexing_completed
          log_message("Ruby LSP indexing completed. Starting TypeGuessr AST traversal.")

          # Get indexable URIs from RubyIndexer configuration
          indexable_uris = index.configuration.indexable_uris
          log_message("Found #{indexable_uris.size} indexed files to traverse.")
          log_message("Using #{WORKER_COUNT} worker threads.")

          # Thread-safe progress tracking
          progress_mutex = Mutex.new
          processed_count = 0
          progress_step = (indexable_uris.size / 10.0).ceil

          # Create a thread pool with work queue
          queue = Thread::Queue.new
          indexable_uris.each { |uri| queue << uri }
          WORKER_COUNT.times { queue << :stop } # Sentinel values to stop workers

          # Start worker threads
          workers = WORKER_COUNT.times.map do
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

      # Re-index a single file by traversing its AST
      def reindex_file(file_path)
        return if !File.exist?(file_path)

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

      private

      def traverse_file_ast(uri)
        file_path = uri.full_path
        return if !file_path || !File.exist?(file_path)

        source = File.read(file_path)
        result = Prism.parse(source)

        # Use a visitor to traverse the AST
        visitor = ::TypeGuessr::Core::ASTAnalyzer.new(file_path)
        result.value.accept(visitor)
      rescue StandardError => e
        log_message("Error parsing #{uri}: #{e.message}")
      end

      # Send a log message to the LSP client
      def log_message(message)
        return if !@message_queue
        return if @message_queue.closed?

        @message_queue << RubyLsp::Notification.window_log_message(
          "[TypeGuessr] #{message}",
          type: RubyLsp::Constant::MessageType::LOG
        )
      end
    end
  end
end
