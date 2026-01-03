# frozen_string_literal: true

require "uri"
require_relative "flow_analyzer"
require_relative "types"
require_relative "logger"

module TypeGuessr
  module Core
    # UserMethodReturnResolver infers return types for user-defined methods
    # Uses FlowAnalyzer to analyze method body and determine return type
    class UserMethodReturnResolver
      MAX_DEPTH = 5

      def initialize(index_adapter)
        @index_adapter = index_adapter
        @cache = {} # { "ClassName#method_name" => Types::Type }
      end

      # Get return type for a user-defined method
      # @param class_name [String] the class name containing the method
      # @param method_name [String] the method name
      # @param depth [Integer] recursion depth (for preventing infinite loops)
      # @return [Types::Type] the inferred return type or Unknown
      def get_return_type(class_name, method_name, depth: 0)
        return Types::Unknown.instance if depth > MAX_DEPTH

        cache_key = "#{class_name}##{method_name}"
        return @cache[cache_key] if @cache.key?(cache_key)

        # 1. Find method entry via index
        entries = @index_adapter.resolve_method(method_name, class_name)
        return Types::Unknown.instance unless entries&.any?

        # 2. Read method source from file
        entry = entries.first
        source = read_method_source(entry)
        return Types::Unknown.instance unless source

        # 3. Analyze with FlowAnalyzer
        result = FlowAnalyzer.new.analyze(source)
        type = result.return_type_for_method(method_name)

        @cache[cache_key] = type
        type
      rescue StandardError => e
        # If anything goes wrong, return Unknown
        Logger.error("UserMethodReturnResolver error", e)
        Types::Unknown.instance
      end

      private

      # Read method source code from file
      # @param entry [RubyIndexer::Entry::Method] the method entry
      # @return [String, nil] the method source code or nil if error
      def read_method_source(entry)
        uri = entry.uri
        file_path = URI(uri.to_s).path
        return nil unless File.exist?(file_path)

        lines = File.readlines(file_path)
        start_line = entry.location.start_line - 1
        end_line = entry.location.end_line - 1

        lines[start_line..end_line].join
      rescue StandardError => _e
        nil
      end
    end
  end
end
