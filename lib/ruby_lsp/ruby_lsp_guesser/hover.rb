# frozen_string_literal: true

require "prism"
require_relative "variable_index"
require_relative "type_matcher"

module RubyLsp
  module Guesser
    # Hover provider that returns a fixed message
    class Hover
      def initialize(response_builder, node_context, dispatcher, global_state = nil)
        @response_builder = response_builder
        @node_context = node_context
        @global_state = global_state

        register_listeners(dispatcher)
      end

      def on_local_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_local_variable_write_node_enter(node)
        add_hover_content(node)
      end

      def on_local_variable_target_node_enter(node)
        add_hover_content(node)
      end

      def on_instance_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_class_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_global_variable_read_node_enter(node)
        add_hover_content(node)
      end

      def on_self_node_enter(node)
        add_hover_content(node)
      end

      def on_required_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_optional_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_rest_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_required_keyword_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_optional_keyword_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_keyword_rest_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_block_parameter_node_enter(node)
        add_hover_content(node)
      end

      def on_forwarding_parameter_node_enter(node)
        add_hover_content(node)
      end

      private

      def register_listeners(dispatcher)
        dispatcher.register(
          self,
          :on_local_variable_read_node_enter,
          :on_local_variable_write_node_enter,
          :on_local_variable_target_node_enter,
          :on_instance_variable_read_node_enter,
          :on_class_variable_read_node_enter,
          :on_global_variable_read_node_enter,
          :on_self_node_enter,
          :on_required_parameter_node_enter,
          :on_optional_parameter_node_enter,
          :on_rest_parameter_node_enter,
          :on_required_keyword_parameter_node_enter,
          :on_optional_keyword_parameter_node_enter,
          :on_keyword_rest_parameter_node_enter,
          :on_block_parameter_node_enter,
          :on_forwarding_parameter_node_enter
        )
      end

      def add_hover_content(node)
        variable_name = extract_variable_name(node)
        return unless variable_name

        # Try to get direct type first
        direct_type = get_direct_type(variable_name, node)
        method_calls = collect_method_calls(variable_name, node)

        content = build_hover_content(variable_name, method_calls, direct_type)
        @response_builder.push(content, category: :documentation) if content
      end

      def extract_variable_name(node)
        case node
        when ::Prism::LocalVariableReadNode, ::Prism::LocalVariableWriteNode
          node.name.to_s
        when ::Prism::LocalVariableTargetNode
          node.name.to_s
        when ::Prism::RequiredParameterNode, ::Prism::OptionalParameterNode
          node.name.to_s
        when ::Prism::RestParameterNode
          node.name&.to_s
        when ::Prism::RequiredKeywordParameterNode, ::Prism::OptionalKeywordParameterNode
          node.name.to_s
        when ::Prism::KeywordRestParameterNode
          node.name&.to_s
        when ::Prism::BlockParameterNode
          node.name&.to_s
        when ::Prism::InstanceVariableReadNode
          node.name.to_s
        when ::Prism::ClassVariableReadNode
          node.name.to_s
        when ::Prism::GlobalVariableReadNode
          node.name.to_s
        when ::Prism::SelfNode
          "self"
        when ::Prism::ForwardingParameterNode
          "..."
        end
      end

      # Get the direct type for a variable (from literal assignment or .new call)
      def get_direct_type(variable_name, node)
        location = node.location
        hover_line = location.start_line

        index = VariableIndex.instance
        scope_type = determine_scope_type(variable_name)
        scope_id = generate_scope_id(scope_type)

        # First, try to find definitions from method call index
        definitions = index.find_definitions(
          var_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # If no exact match, try broader search
        if definitions.empty?
          definitions = index.find_definitions(
            var_name: variable_name,
            scope_type: scope_type
          )
        end

        # Find the closest definition before the hover line
        best_match = definitions
                     .select { |def_info| def_info[:def_line] <= hover_line }
                     .max_by { |def_info| def_info[:def_line] }

        if best_match
          # Get the type for this definition
          type = index.get_variable_type(
            file_path: best_match[:file_path],
            scope_type: best_match[:scope_type],
            scope_id: best_match[:scope_id],
            var_name: variable_name,
            def_line: best_match[:def_line],
            def_column: best_match[:def_column]
          )
          return type if type
        end

        # Fallback: search type index directly (for variables with type but no method calls)
        find_direct_type_from_index(variable_name, scope_type, scope_id, hover_line)
      end

      # Search type index directly for variables that have types but no method calls
      def find_direct_type_from_index(variable_name, scope_type, scope_id, hover_line)
        index = VariableIndex.instance

        # Use the public API to find variable type at location
        index.find_variable_type_at_location(
          var_name: variable_name,
          scope_type: scope_type,
          max_line: hover_line,
          scope_id: scope_id
        )
      end

      def collect_method_calls(variable_name, node)
        location = node.location
        hover_line = location.start_line
        location.start_column

        index = VariableIndex.instance
        scope_type = determine_scope_type(variable_name)
        scope_id = generate_scope_id(scope_type)

        # Try to find definitions matching the exact scope
        definitions = index.find_definitions(
          var_name: variable_name,
          scope_type: scope_type,
          scope_id: scope_id
        )

        # If no exact match, try without scope_id (broader search)
        if definitions.empty?
          definitions = index.find_definitions(
            var_name: variable_name,
            scope_type: scope_type
          )
        end

        # Find the closest definition that appears before the hover line
        best_match = definitions
                     .select { |def_info| def_info[:def_line] <= hover_line }
                     .max_by { |def_info| def_info[:def_line] }

        if best_match
          # Use the exact variable definition location for precise results
          calls = index.get_method_calls(
            file_path: best_match[:file_path],
            scope_type: best_match[:scope_type],
            scope_id: best_match[:scope_id],
            var_name: variable_name,
            def_line: best_match[:def_line],
            def_column: best_match[:def_column]
          )
          calls.map { |call| call[:method] }.uniq
        else
          # Fallback: collect method calls from all matching definitions
          method_names = []
          definitions.each do |def_info|
            calls = index.get_method_calls(
              file_path: def_info[:file_path],
              scope_type: def_info[:scope_type],
              scope_id: def_info[:scope_id],
              var_name: variable_name,
              def_line: def_info[:def_line],
              def_column: def_info[:def_column]
            )
            method_names.concat(calls.map { |call| call[:method] })
          end
          method_names.uniq.take(20)
        end
      end

      # Determine the scope type based on variable name
      def determine_scope_type(var_name)
        if var_name.start_with?("@@")
          :class_variables
        elsif var_name.start_with?("@")
          :instance_variables
        else
          :local_variables
        end
      end

      # Generate scope ID from node context
      # - For instance/class variables: "ClassName"
      # - For local variables: "ClassName#method_name"
      def generate_scope_id(scope_type)
        nesting = @node_context.nesting
        # nesting may contain strings or objects with name method
        class_path = nesting.map { |n| n.is_a?(String) ? n : n.name }.join("::")

        if scope_type == :local_variables
          # Try to find enclosing method name
          enclosing_method = @node_context.call_node&.name&.to_s
          if enclosing_method && !class_path.empty?
            "#{class_path}##{enclosing_method}"
          elsif enclosing_method
            enclosing_method
          elsif !class_path.empty?
            class_path
          else
            "(top-level)"
          end
        elsif !class_path.empty?
          class_path
        else
          "(top-level)"
        end
      end

      def build_hover_content(variable_name, method_calls, direct_type = nil)
        # Priority 1: Use direct type inference (from literal or .new call)
        return "**Inferred type:** `#{direct_type}`" if direct_type

        # Priority 2: Try to infer type if we have method calls and global_state is available
        if !method_calls.empty? && @global_state
          inferred_type = infer_type_from_methods(method_calls)

          # Debug logging for method calls
          if debug_mode? && !method_calls.empty?
            warn("[RubyLspGuesser] Variable '#{variable_name}' method calls: #{method_calls.inspect}")
          end

          return inferred_type if inferred_type
        end

        # Fallback: show method calls only in debug mode, otherwise show nothing
        return unless debug_mode?

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
      def debug_mode?
        # First check environment variable
        return true if %w[1 true].include?(ENV["RUBY_LSP_GUESSER_DEBUG"])

        # Then check config file
        @debug_mode ||= load_debug_mode_from_config
      end

      # Load debug mode setting from .ruby-lsp-guesser.yml
      def load_debug_mode_from_config
        config_path = File.join(Dir.pwd, ".ruby-lsp-guesser.yml")
        return false unless File.exist?(config_path)

        require "yaml"
        config = YAML.load_file(config_path)
        config["debug"] == true
      rescue StandardError => e
        warn("[RubyLspGuesser] Error loading config file: #{e.message}")
        false
      end

      # Infer type from method calls using TypeMatcher
      # Returns a formatted string with the inferred type, or nil if no inference is possible
      def infer_type_from_methods(method_calls)
        return nil unless @global_state

        index = @global_state.index
        matcher = TypeMatcher.new(index)
        matching_types = matcher.find_matching_types(method_calls)

        case matching_types.size
        when 0
          nil # No type inferred, fallback to method list
        when 1
          "**Inferred type:** `#{matching_types.first}`"
        else
          # Multiple matches - ambiguous
          "**Ambiguous type** (could be: #{matching_types.map { |t| "`#{t}`" }.join(", ")})"
        end
      end
    end
  end
end
