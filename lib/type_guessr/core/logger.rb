# frozen_string_literal: true

module TypeGuessr
  module Core
    # Unified logging interface for TypeGuessr
    # Uses TYPE_GUESSR_DEBUG environment variable to control output
    module Logger
      module_function

      # Log debug message with optional context
      # @param msg [String] the debug message
      # @param context [Hash] optional context information
      def debug(msg, context = {})
        return unless debug_enabled?

        output = "[TypeGuessr:DEBUG] #{msg}"
        output += " #{context.inspect}" unless context.empty?
        warn output
      end

      # Log error message with optional exception
      # @param msg [String] the error message
      # @param exception [Exception, nil] optional exception for backtrace
      def error(msg, exception = nil)
        return unless debug_enabled?

        warn "[TypeGuessr:ERROR] #{msg}"
        return unless exception

        warn "  #{exception.class}: #{exception.message}"
        warn exception.backtrace.first(5).map { |l| "    #{l}" }.join("\n")
      end

      # Check if debug mode is enabled
      # @return [Boolean] true if TYPE_GUESSR_DEBUG is set
      def debug_enabled?
        # Don't cache - check ENV every time during tests
        %w[1 true].include?(ENV.fetch("TYPE_GUESSR_DEBUG", nil))
      end
    end
  end
end
