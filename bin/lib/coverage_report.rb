# frozen_string_literal: true

module CoverageRunner
  # Calculates type inference coverage statistics for a codebase
  # Provides node coverage (typed/total) and signature score metrics
  class CoverageReport
    IR = TypeGuessr::Core::IR
    Types = TypeGuessr::Core::Types

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

    # Collect untyped nodes with optional filtering and limiting
    # @param filter [String, nil] Comma-separated node type names to filter (e.g., "ParamNode,CallNode")
    # @param limit [Integer, nil] Maximum number of nodes to return
    # @return [Array<Hash>] Array of node info hashes with :type, :name, :file, :line, :scope, :reason
    def collect_untyped_nodes(filter: nil, limit: nil)
      nodes = collect_all_nodes
      nodes = nodes.reject { |n| n.is_a?(IR::DefNode) }

      # Filter to untyped nodes only
      untyped = nodes.reject { |node| typed?(node) }

      # Apply node type filter if specified
      if filter
        filter_types = filter.split(",").map(&:strip)
        untyped = untyped.select { |n| filter_types.include?(node_type_name(n)) }
      end

      # Apply limit if specified
      untyped = untyped.take(limit) if limit

      # Extract info for each node
      untyped.map { |node| extract_node_info(node) }
    end

    # Get total count of untyped nodes (excluding DefNode)
    # @return [Integer]
    def total_untyped_count
      nodes = collect_all_nodes
      nodes = nodes.reject { |n| n.is_a?(IR::DefNode) }
      nodes.count { |node| !typed?(node) }
    end

    private def calculate_node_coverage
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
    private def calculate_signature_score
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
    private def collect_all_nodes
      @location_index.all_files.flat_map { |file_path| @location_index.nodes_for_file(file_path) }
    end

    # Collect project methods from the method registry
    # Iterates through all registered class/method combinations
    # @return [Array<IR::DefNode>]
    private def collect_project_methods
      @method_registry.search("").map do |_class_name, _method_name, def_node|
        def_node
      end
    end

    # Build breakdown by node type
    # @param nodes [Array<IR::Node>]
    # @return [Hash{String => Hash}]
    private def build_breakdown(nodes)
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
    private def count_typed_nodes(nodes)
      nodes.count { |node| typed?(node) }
    end

    # Check if a node has a known type
    # Returns false if inference fails (e.g., circular dependencies)
    # @param node [IR::Node]
    # @return [Boolean]
    private def typed?(node)
      result = @resolver.infer(node)
      !result.type.is_a?(Types::Unknown)
    rescue SystemStackError, StandardError
      false
    end

    # Calculate slot score for a method
    # Score = typed_slots / total_slots
    # @param def_node [IR::DefNode]
    # @return [Float]
    private def method_slot_score(def_node)
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
    private def calculate_percentage(numerator, denominator)
      return 0.0 unless denominator.positive?

      (numerator.to_f / denominator * 100).round(1)
    end

    # Get the simple class name for a node (e.g., "ParamNode")
    # @param node [IR::Node]
    # @return [String]
    private def node_type_name(node)
      node.class.name.split("::").last
    end

    # Extract displayable info from a node
    # @param node [IR::Node]
    # @return [Hash]
    private def extract_node_info(node)
      result = begin
        @resolver.infer(node)
      rescue StandardError
        nil
      end

      {
        type: node_type_name(node),
        name: node_name(node),
        file: find_file_for_node(node),
        line: node.loc&.line,
        scope: find_scope_for_node(node),
        reason: result&.reason || "inference failed"
      }
    end

    # Get a human-readable name for a node
    # @param node [IR::Node]
    # @return [String, nil]
    private def node_name(node)
      case node
      when IR::ParamNode, IR::LocalWriteNode
        node.name.to_s
      when IR::InstanceVariableWriteNode, IR::ClassVariableWriteNode
        node.name.to_s
      when IR::CallNode
        node.method_name.to_s
      when IR::ConstantNode
        node.name.to_s
      when IR::LiteralNode
        node.type.to_s
      end
    end

    # Find the file path containing a node
    # @param node [IR::Node]
    # @return [String, nil]
    private def find_file_for_node(node)
      @location_index.all_files.find do |file_path|
        @location_index.nodes_for_file(file_path).include?(node)
      end
    end

    # Find the scope ID for a node
    # @param node [IR::Node]
    # @return [String, nil]
    private def find_scope_for_node(node)
      @location_index.all_files.each do |file_path|
        scope = @location_index.scope_for_node(file_path, node)
        return scope if scope
      end
      nil
    end
  end
end
