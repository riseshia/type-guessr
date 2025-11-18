# frozen_string_literal: true

module TypeGuessr
  module Integrations
    module RubyLsp
      # Builds hover content from type information
      # Handles debug mode settings and content formatting
      class HoverContentBuilder
        def initialize(global_state = nil)
          @global_state = global_state
        end

        # Build hover content from type information
        # @param type_info [Hash] hash with :variable_name, :direct_type, and :method_calls keys
        # @param matching_types [Array<String>] array of matching type names from inference
        # @return [String, nil] the hover content or nil
        def build(type_info, matching_types: [])
          variable_name = type_info[:variable_name]
          direct_type = type_info[:direct_type]
          method_calls = type_info[:method_calls] || []

          # Priority 1: Use direct type inference (from literal or .new call)
          return "**Inferred type:** `#{direct_type}`" if direct_type

          # Priority 2: Try to infer type if we have method calls and matching types
          unless matching_types.empty?
            # Debug logging for method calls
            warn("[RubyLspGuesser] Variable '#{variable_name}' method calls: #{method_calls.inspect}") if debug_mode? && !method_calls.empty?

            return format_inferred_types(matching_types)
          end

          # Fallback: show method calls only in debug mode, otherwise show nothing
          return unless debug_mode?

          format_debug_content(variable_name, method_calls)
        end

        private

        # Format inferred types based on count
        # @param matching_types [Array<String>] array of matching type names
        # @return [String] formatted type string
        def format_inferred_types(matching_types)
          case matching_types.size
          when 1
            "**Inferred type:** `#{matching_types.first}`"
          else
            # Multiple matches - ambiguous
            "**Ambiguous type** (could be: #{matching_types.map { |t| "`#{t}`" }.join(", ")})"
          end
        end

        # Format debug content showing method calls
        # @param variable_name [String] the variable name
        # @param method_calls [Array<String>] array of method names
        # @return [String] formatted debug content
        def format_debug_content(variable_name, method_calls)
          if method_calls.empty?
            warn("[RubyLspGuesser] Variable '#{variable_name}': No method calls found")
            "No method calls found."
          else
            warn("[RubyLspGuesser] Variable '#{variable_name}' method calls: #{method_calls.inspect}")
            content = "Method calls:\n"
            method_calls.each do |method_name|
              content += "- `#{method_name}`\n"
            end
            content
          end
        end

        # Check if debug mode is enabled via environment variable or config file
        # @return [Boolean] true if debug mode is enabled
        def debug_mode?
          # First check environment variable
          return true if %w[1 true].include?(ENV["TYPE_GUESSR_DEBUG"])

          # Then check config file
          @debug_mode ||= load_debug_mode_from_config
        end

        # Load debug mode setting from .type-guessr.yml
        # @return [Boolean] true if debug mode is enabled in config
        def load_debug_mode_from_config
          config_path = File.join(Dir.pwd, ".type-guessr.yml")
          return false unless File.exist?(config_path)

          require "yaml"
          config = YAML.load_file(config_path)
          config["debug"] == true
        rescue StandardError => e
          warn("[TypeGuessr] Error loading config file: #{e.message}")
          false
        end
      end
    end
  end
end
