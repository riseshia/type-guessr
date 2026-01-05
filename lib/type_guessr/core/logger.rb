# frozen_string_literal: true

require_relative "../../ruby_lsp/type_guessr/config"

module TypeGuessr
  module Core
    # Unified logging interface for TypeGuessr
    # Uses Config.debug? to control output
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
      # @return [Boolean] true if Config.debug? returns true
      def debug_enabled?
        RubyLsp::TypeGuessr::Config.debug?
      end
    end
  end
end
