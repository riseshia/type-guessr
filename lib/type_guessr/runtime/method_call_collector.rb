# frozen_string_literal: true

require "prism"

module TypeGuessr
  module Runtime
    # Lightweight Prism AST walker that extracts method calls on
    # local variables and parameters. No IR, no Resolver dependency.
    #
    # For each variable/parameter in a file, collects the set of
    # method names called on it via explicit receiver (e.g., `foo.bar`).
    class MethodCallCollector
      Finding = Data.define(:file, :line, :name, :node_type, :called_methods)

      # @param file_path [String]
      # @param source [String]
      # @return [Array<Finding>]
      def collect(file_path, source)
        parsed = Prism.parse(source)
        return [] unless parsed.value

        var_methods = Hash.new { |h, k| h[k] = Set.new }
        var_locations = {}
        param_names = Set.new

        walk(parsed.value, var_methods, var_locations, param_names)

        var_methods.filter_map do |var_name, methods|
          next if methods.empty?

          Finding.new(
            file: file_path,
            line: var_locations[var_name],
            name: var_name.to_s,
            node_type: param_names.include?(var_name) ? "ParamNode" : "LocalVariable",
            called_methods: methods.to_a.map(&:to_s)
          )
        end
      end

      private def walk(node, var_methods, var_locations, param_names)
        case node
        when Prism::DefNode
          new_params = Set.new
          collect_param_names(node.parameters, new_params) if node.parameters
          walk(node.body, var_methods, var_locations, param_names | new_params) if node.body

        when Prism::BlockNode, Prism::LambdaNode
          block_params = Set.new
          if node.parameters
            params_node = node.parameters
            params_node = params_node.parameters if params_node.is_a?(Prism::BlockParametersNode)
            collect_param_names(params_node, block_params) if params_node
          end

          node.body&.child_nodes&.compact&.each do |child| # rubocop:disable Style/SafeNavigationChainLength
            walk(child, var_methods, var_locations, param_names | block_params)
          end

        when Prism::CallNode
          if node.receiver.is_a?(Prism::LocalVariableReadNode)
            var_name = node.receiver.name
            var_methods[var_name] << node.name
            var_locations[var_name] ||= node.receiver.location.start_line
          end

          walk(node.receiver, var_methods, var_locations, param_names) if node.receiver
          node.arguments&.arguments&.each { |arg| walk(arg, var_methods, var_locations, param_names) }
          walk(node.block, var_methods, var_locations, param_names) if node.block

        else
          node.child_nodes.compact.each { |child| walk(child, var_methods, var_locations, param_names) }
        end
      end

      private def collect_param_names(params_node, set)
        return unless params_node.is_a?(Prism::ParametersNode)

        params_node.requireds.each { |p| set << p.name if p.respond_to?(:name) }
        params_node.optionals.each { |p| set << p.name if p.respond_to?(:name) }
        params_node.keywords.each { |p| set << p.name if p.respond_to?(:name) }
        set << params_node.rest.name if params_node.rest.respond_to?(:name) && params_node.rest.name
        set << params_node.keyword_rest.name if params_node.keyword_rest.respond_to?(:name) && params_node.keyword_rest.name
      end
    end
  end
end
