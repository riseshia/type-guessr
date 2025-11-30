# frozen_string_literal: true

require_relative "type_matcher"

module RubyLsp
  module TypeGuessr
    # Builds hover content from type information
    # Handles debug mode settings and content formatting
    class HoverContentBuilder
      def initialize(global_state = nil)
        @global_state = global_state
      end

      # Build hover content from type information
      # @param type_info [Hash] hash with :variable_name, :direct_type, and :method_calls keys
      # @param matching_types [Array<String>] array of matching type names from inference
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [String, nil] the hover content or nil
      def build(type_info, matching_types: [], type_entries: {})
        variable_name = type_info[:variable_name]
        direct_type = type_info[:direct_type]
        method_calls = type_info[:method_calls] || []

        # Debug logging for method calls (always log when debug mode, regardless of matching_types)
        warn("[TypeGuessr] Variable '#{variable_name}' method calls: #{method_calls.inspect}") if debug_mode?

        # Priority 1: Use direct type inference (from literal or .new call)
        if direct_type
          formatted_type = format_type_with_link(direct_type, type_entries[direct_type])
          return "**Guessed type:** #{formatted_type}"
        end

        # Priority 2: Try to guess type if we have method calls and matching types
        return format_guessed_types(matching_types, type_entries) if !matching_types.empty?

        # Fallback: show method calls only in debug mode, otherwise show nothing
        return if !debug_mode?

        format_debug_content(variable_name, method_calls)
      end

      private

      # Format guessed types based on count
      # @param matching_types [Array<String>] array of matching type names
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [String] formatted type string
      def format_guessed_types(matching_types, type_entries)
        case matching_types.size
        when 1
          type_name = matching_types.first
          formatted_type = format_type_with_link(type_name, type_entries[type_name])
          "**Guessed type:** #{formatted_type}"
        else
          # Multiple matches - ambiguous (no links needed)
          # Check if results were truncated (indicated by '...' marker)
          truncated = matching_types.last == TypeMatcher::TRUNCATED_MARKER
          display_types = truncated ? matching_types[0...-1] : matching_types
          type_list = display_types.map { |t| "`#{t}`" }.join(", ")
          type_list += ", ..." if truncated
          "**Ambiguous type** (could be: #{type_list})"
        end
      end

      # Format a type name with link to definition if entry is available
      # @param type_name [String] the type name
      # @param entry [RubyIndexer::Entry, nil] the entry for the type
      # @return [String] formatted type, possibly with link
      def format_type_with_link(type_name, entry)
        return "`#{type_name}`" if entry.nil?

        location_link = build_location_link(entry)
        return "`#{type_name}`" if location_link.nil?

        "[`#{type_name}`](#{location_link})"
      end

      # Build a location link from an entry
      # @param entry [RubyIndexer::Entry] the entry
      # @return [String, nil] the location link or nil
      def build_location_link(entry)
        uri = entry.uri
        return nil if uri.nil?

        location = entry_location(entry)
        return nil if location.nil?

        "#{uri}#L#{location.start_line},#{location.start_column + 1}-#{location.end_line},#{location.end_column + 1}"
      end

      # Get the appropriate location from an entry
      # Namespace entries have name_location, others use location
      # @param entry [RubyIndexer::Entry] the entry
      # @return [RubyIndexer::Location, nil] the location
      def entry_location(entry)
        # Namespace entries (Class, Module) have name_location for precise linking
        if entry.respond_to?(:name_location)
          entry.name_location
        else
          entry.location
        end
      end

      # Format debug content showing method calls
      # @param variable_name [String] the variable name
      # @param method_calls [Array<String>] array of method names
      # @return [String] formatted debug content
      def format_debug_content(_variable_name, method_calls)
        if method_calls.empty?
          "No method calls found."
        else
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
        return false if !File.exist?(config_path)

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
