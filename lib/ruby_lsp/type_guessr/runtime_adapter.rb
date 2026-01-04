# frozen_string_literal: true

require "prism"
require_relative "../../type_guessr/core/converter/prism_converter"
require_relative "../../type_guessr/core/index/location_index"
require_relative "../../type_guessr/core/inference/resolver"
require_relative "../../type_guessr/core/rbs_provider"

module RubyLsp
  module TypeGuessr
    # RuntimeAdapter manages the IR graph and inference for TypeGuessr
    # Converts files to IR graphs and provides type inference
    class RuntimeAdapter
      def initialize(global_state)
        @global_state = global_state
        @converter = ::TypeGuessr::Core::Converter::PrismConverter.new
        @location_index = ::TypeGuessr::Core::Index::LocationIndex.new
        @resolver = ::TypeGuessr::Core::Inference::Resolver.new(::TypeGuessr::Core::RBSProvider.instance)
      end

      # Index a file by converting its Prism AST to IR graph
      # @param uri [URI::Generic] File URI
      # @param document [RubyLsp::Document] Document to index
      def index_file(uri, document)
        file_path = uri.to_standardized_path
        return unless file_path

        # Clear existing index for this file
        @location_index.remove_file(file_path)
        @resolver.clear_cache

        # Parse and convert to IR
        parsed = document.parse_result
        return unless parsed.value

        # Convert statements to IR nodes
        parsed.value.statements&.body&.each do |stmt|
          node = @converter.convert(stmt)
          @location_index.add(file_path, node) if node
        end

        # Finalize the index for efficient lookups
        @location_index.finalize!
      end

      # Index source code directly (for testing)
      # @param uri_string [String] File URI as string
      # @param source [String] Source code to index
      def index_source(uri_string, source)
        file_path = URI(uri_string).to_standardized_path || uri_string
        return unless file_path

        # Clear existing index for this file
        @location_index.remove_file(file_path)
        @resolver.clear_cache

        # Parse source code
        parsed = Prism.parse(source)
        return unless parsed.value

        # Convert statements to IR nodes
        parsed.value.statements&.body&.each do |stmt|
          node = @converter.convert(stmt)
          @location_index.add(file_path, node) if node
        end

        # Finalize the index for efficient lookups
        @location_index.finalize!
      end

      # Find IR node at the given position
      # @param uri [URI::Generic] File URI
      # @param line [Integer] Line number (0-indexed)
      # @param column [Integer] Column number (0-indexed)
      # @return [TypeGuessr::Core::IR::Node, nil] IR node at position
      def find_node_at(uri, line, column)
        file_path = uri.to_standardized_path
        return nil unless file_path

        # Convert from 0-indexed to 1-indexed line
        @location_index.find(file_path, line + 1, column)
      end

      # Infer type for an IR node
      # @param node [TypeGuessr::Core::IR::Node] IR node
      # @return [TypeGuessr::Core::Inference::Result] Inference result
      def infer_type(node)
        @resolver.infer(node)
      end

      # Get statistics about the index
      # @return [Hash] Statistics
      def stats
        @location_index.stats
      end
    end
  end
end
