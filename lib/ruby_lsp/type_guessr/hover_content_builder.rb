# frozen_string_literal: true

require_relative "type_matcher"
require_relative "config"
require_relative "../../type_guessr/core/type_formatter"

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
      # @param matching_types [Array<TypeGuessr::Core::Types::Type>] array of matching types from inference
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [String, nil] the hover content or nil
      def build(type_info, matching_types: [], type_entries: {})
        method_calls = type_info[:method_calls] || []
        content, reason, inferred = build_type_content(type_info, matching_types, type_entries)

        # Return nil if no content and not in debug mode
        return nil if content.nil? && !debug_mode?

        append_debug_info(content, reason, inferred, method_calls)
      end

      # Core layer shortcuts
      Types = ::TypeGuessr::Core::Types
      TypeFormatter = ::TypeGuessr::Core::TypeFormatter
      private_constant :Types, :TypeFormatter

      private

      # Build type content from available type information
      # @param type_info [Hash] hash with :direct_type and :method_calls keys
      # @param matching_types [Array<TypeGuessr::Core::Types::Type>] array of matching types
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [Array<String, Symbol, Object>] tuple of [content, reason, inferred_type]
      def build_type_content(type_info, matching_types, type_entries)
        direct_type = type_info[:direct_type]

        # Priority 1: Use direct type inference (from literal or .new call)
        # Skip if direct_type is Unknown - let it fall through to method-based inference
        if direct_type && direct_type != Types::Unknown.instance
          type_name = extract_type_name(direct_type)
          formatted_type = format_type_with_link(direct_type, type_entries[type_name])
          content = "**Guessed type:** #{formatted_type}"
          return [content, :direct_type, direct_type]
        end

        # Priority 2: Try to guess type if we have method calls and matching types (Phase 6)
        if !matching_types.empty?
          content = format_guessed_types(matching_types, type_entries)
          return [content, :method_calls, matching_types]
        end

        # Priority 3: Show untyped if we have method calls but no matching types
        return ["**Guessed type:** untyped", :untyped, nil] if type_info[:method_calls]&.any?

        # No type information available
        [nil, :unknown, nil]
      end

      # Append debug information to content if debug mode is enabled
      # @param content [String, nil] the base content
      # @param reason [Symbol] the inference reason (:direct_type, :method_calls, :unknown)
      # @param inferred [Object] the inferred type(s)
      # @param method_calls [Array<String>] array of method names
      # @return [String, nil] content with debug info appended, or nil
      def append_debug_info(content, reason, inferred, method_calls)
        return content unless debug_mode?

        base = content || ""
        base + format_debug_reason(reason, inferred, method_calls)
      end

      # Format guessed types based on count
      # @param matching_types [Array<TypeGuessr::Core::Types::Type>] array of matching types
      # @param type_entries [Hash<String, Entry>] map of type name to entry for linking
      # @return [String] formatted type string
      def format_guessed_types(matching_types, type_entries)
        # Check if results were truncated (4+ matches) - show untyped
        truncated = matching_types.last == TypeMatcher::TRUNCATED_MARKER
        return "**Guessed type:** untyped" if truncated

        case matching_types.size
        when 1
          type_obj = matching_types.first
          type_name = extract_type_name(type_obj)
          formatted_type = format_type_with_link(type_obj, type_entries[type_name])
          "**Guessed type:** #{formatted_type}"
        else
          # 2-3 matches - ambiguous (no links needed)
          type_list = format_inline_list(matching_types)
          "**Ambiguous type** (could be: #{type_list})"
        end
      end

      # Format a type with link to definition if entry is available
      # @param type_obj [TypeGuessr::Core::Types::Type] the type object
      # @param entry [RubyIndexer::Entry, nil] the entry for the type
      # @return [String] formatted type, possibly with link
      def format_type_with_link(type_obj, entry)
        formatted = TypeFormatter.format(type_obj)
        return "`#{formatted}`" if entry.nil?

        location_link = build_location_link(entry)
        return "`#{formatted}`" if location_link.nil?

        "[`#{formatted}`](#{location_link})"
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
      # @param reason_type [Symbol] :direct_type, :method_calls, :untyped, or :unknown
      # @param inferred_type [TypeGuessr::Core::Types::Type, Array<TypeGuessr::Core::Types::Type>, nil] the inferred type(s)
      # @param method_calls [Array<String>] array of method names
      # @return [String] formatted debug reason
      def format_debug_reason(reason_type, inferred_type, method_calls)
        content = "\n\n---\n**[TypeGuessr Debug] Inference basis:**\n"

        case reason_type
        when :direct_type
          formatted_type = TypeFormatter.format(inferred_type)
          content += "- Reason: `.new` call or literal assignment\n"
          content += "- Direct type: `#{formatted_type}`\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        when :method_calls
          types = Array(inferred_type)
          content += "- Reason: Method call pattern matching\n"
          content += "- Matched types: #{format_inline_list(types)}\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        when :untyped
          content += "- Reason: No unique type match found\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        when :unknown
          content += "- Reason: Unknown\n"
          content += "- Method calls: #{format_method_calls_list(method_calls)}\n"
        end

        content
      end

      # Format an array of items as inline backtick-wrapped, comma-separated list
      # @param items [Array] array of items to format (can be Types or Strings)
      # @return [String] formatted inline list (e.g., "`item1`, `item2`")
      def format_inline_list(items)
        items.map do |item|
          formatted = item.is_a?(String) ? item : TypeFormatter.format(item)
          "`#{formatted}`"
        end.join(", ")
      end

      # Format method calls as a readable list
      # @param method_calls [Array<String>] array of method names
      # @return [String] formatted method calls
      def format_method_calls_list(method_calls)
        return "(none)" if method_calls.empty?

        format_inline_list(method_calls)
      end

      # Extract type name from a Types object
      # @param type_obj [TypeGuessr::Core::Types::Type] the type object
      # @return [String] the type name
      def extract_type_name(type_obj)
        case type_obj
        when Types::ClassInstance
          type_obj.name
        else
          TypeFormatter.format(type_obj)
        end
      end

      # Check if debug mode is enabled via environment variable or config file
      # @return [Boolean] true if debug mode is enabled
      def debug_mode?
        Config.debug?
      end
    end
  end
end
