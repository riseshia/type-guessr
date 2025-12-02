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
      # @param type_info [Hash] hash with :direct_type and :method_calls keys
      # @param matching_types [Array<String>] array of matching type names from inference
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [String, nil] the hover content or nil
      def build(type_info, matching_types: [], type_entries: {})
        direct_type = type_info[:direct_type]
        method_calls = type_info[:method_calls] || []

        # Priority 1: Use direct type inference (from literal or .new call)
        if direct_type
          formatted_type = format_type_with_link(direct_type, type_entries[direct_type])
          result = "**Guessed type:** #{formatted_type}"
          result += format_debug_reason(:direct_type, direct_type, method_calls) if debug_mode?
          return result
        end

        # Priority 2: Try to guess type if we have method calls and matching types
        if !matching_types.empty?
          result = format_guessed_types(matching_types, type_entries)
          result += format_debug_reason(:method_calls, matching_types, method_calls) if debug_mode?
          return result
        end

        # Fallback: show method calls only in debug mode, otherwise show nothing
        return if !debug_mode?

        format_debug_reason(:unknown, nil, method_calls)
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

      # Format debug reason showing inference basis
      # @param reason_type [Symbol] :direct_type, :method_calls, or :unknown
      # @param inferred_type [String, Array<String>, nil] the inferred type(s)
      # @param method_calls [Array<String>] array of method names
      # @return [String] formatted debug reason
      def format_debug_reason(reason_type, inferred_type, method_calls)
        content = "\n\n---\n**[TypeGuessr Debug] Inference basis:**\n"

        case reason_type
        when :direct_type
          content += "- Reason: `.new` call or literal assignment\n"
          content += "- Direct type: `#{inferred_type}`\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        when :method_calls
          types = Array(inferred_type)
          content += "- Reason: Method call pattern matching\n"
          content += "- Matched types: #{types.map { |t| "`#{t}`" }.join(", ")}\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        when :unknown
          content += "- Reason: Unknown\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        end

        content
      end

      # Format method calls as a readable list
      # @param method_calls [Array<String>] array of method names
      # @return [String] formatted method calls
      def format_method_calls_list(method_calls)
        return "(none)" if method_calls.empty?

        method_calls.map { |m| "`#{m}`" }.join(", ")
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
