# frozen_string_literal: true

require_relative "ir/nodes"
require_relative "types"

module TypeGuessr
  module Core
    # Calculates type inference coverage statistics for a codebase
    # Provides node coverage (typed/total) and signature score metrics
    class CoverageReport
      # @param location_index [Index::LocationIndex] Index containing all IR nodes
      # @param resolver [Inference::Resolver] Resolver for inferring node types
      # @param method_registry [Registry::MethodRegistry] Registry of project methods
      def initialize(location_index, resolver, method_registry)
        @location_index = location_index
        @resolver = resolver
        @method_registry = method_registry
      end

      # Generate coverage report
      # @return [Hash] Report with :node_coverage and :signature_score
      def generate
        {
          node_coverage: calculate_node_coverage,
          signature_score: calculate_signature_score
        }
      end

      private

      # Calculate node-level type coverage
      # Excludes DefNode to avoid duplicate counting (params/return are already counted)
      # @return [Hash] Coverage stats with :total, :typed, :percentage, :breakdown
      def calculate_node_coverage
        nodes = collect_all_nodes
        # Exclude DefNode - it would double-count params and return
        nodes = nodes.reject { |n| n.is_a?(IR::DefNode) }

        breakdown = build_breakdown(nodes)
        total = nodes.size
        typed = count_typed_nodes(nodes)
        percentage = calculate_percentage(typed, total)

        {
          total: total,
          typed: typed,
          percentage: percentage,
          breakdown: breakdown
        }
      end

      # Calculate signature score for project methods
      # Score = average of (typed_slots / total_slots) for each method
      # Slots = parameters + return type
      # @return [Hash] Score stats with :method_count, :average_score
      def calculate_signature_score
        methods = collect_project_methods
        return { method_count: 0, average_score: 0.0 } if methods.empty?

        scores = methods.map { |def_node| method_slot_score(def_node) }
        average = scores.sum / scores.size

        {
          method_count: methods.size,
          average_score: average.round(2)
        }
      end

      # Collect all nodes from the index
      # @return [Array<IR::Node>]
      def collect_all_nodes
        @location_index.all_files.flat_map { |file_path| @location_index.nodes_for_file(file_path) }
      end

      # Collect project methods from the method registry
      # Iterates through all registered class/method combinations
      # @return [Array<IR::DefNode>]
      def collect_project_methods
        @method_registry.search("").map do |_class_name, _method_name, def_node|
          def_node
        end
      end

      # Build breakdown by node type
      # @param nodes [Array<IR::Node>]
      # @return [Hash{String => Hash}]
      def build_breakdown(nodes)
        grouped = nodes.group_by { |n| n.class.name.split("::").last }
        grouped.transform_values do |group_nodes|
          typed_count = count_typed_nodes(group_nodes)
          {
            total: group_nodes.size,
            typed: typed_count,
            percentage: calculate_percentage(typed_count, group_nodes.size)
          }
        end
      end

      # Count nodes that have a known (non-Unknown) type
      # @param nodes [Array<IR::Node>]
      # @return [Integer]
      def count_typed_nodes(nodes)
        nodes.count { |node| typed?(node) }
      end

      # Check if a node has a known type
      # Returns false if inference fails (e.g., circular dependencies)
      # @param node [IR::Node]
      # @return [Boolean]
      def typed?(node)
        result = @resolver.infer(node)
        !result.type.is_a?(Types::Unknown)
      rescue SystemStackError, StandardError
        false
      end

      # Calculate slot score for a method
      # Score = typed_slots / total_slots
      # @param def_node [IR::DefNode]
      # @return [Float]
      def method_slot_score(def_node)
        params = def_node.params || []
        total_slots = params.size + 1 # params + return
        typed_slots = params.count { |param| typed?(param) }
        typed_slots += 1 if typed?(def_node)

        total_slots.positive? ? typed_slots.to_f / total_slots : 0.0
      end

      # Calculate percentage with zero-division protection
      # @param numerator [Integer]
      # @param denominator [Integer]
      # @return [Float]
      def calculate_percentage(numerator, denominator)
        return 0.0 unless denominator.positive?

        (numerator.to_f / denominator * 100).round(1)
      end
    end
  end
end
