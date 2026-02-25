# frozen_string_literal: true

require_relative "../type_serializer"

module TypeGuessr
  module Core
    module Cache
      # Extracts method signatures from indexed gem files.
      # Iterates DefNodes in the method registry and builds serialized signatures.
      class GemSignatureExtractor
        # @param signature_builder [SignatureBuilder]
        # @param method_registry [Registry::MethodRegistry]
        # @param location_index [Index::LocationIndex]
        def initialize(signature_builder:, method_registry:, location_index:)
          @signature_builder = signature_builder
          @method_registry = method_registry
          @location_index = location_index
        end

        # Extract all method signatures from indexed gem files
        # @param gem_files [Array<String>] File paths belonging to this gem
        # @param timeout [Float, nil] Max seconds for inference. Returns nil on timeout.
        # @return [Hash, nil] { instance_methods:, class_methods: } or nil on timeout
        def extract(gem_files, timeout: nil)
          gem_def_nodes = collect_def_nodes(gem_files)
          instance_methods = {}
          class_methods = {}
          deadline = timeout ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout : nil
          check_counter = 0

          @method_registry.each_entry do |class_name, method_name, def_node|
            next unless gem_def_nodes.include?(def_node)

            if deadline
              check_counter += 1
              return nil if (check_counter % 100).zero? && Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            end

            sig = @signature_builder.build_from_def_node(def_node)
            serialized = serialize_signature(sig)

            if def_node.singleton
              class_methods[class_name] ||= {}
              class_methods[class_name][method_name] = serialized
            else
              instance_methods[class_name] ||= {}
              instance_methods[class_name][method_name] = serialized
            end

            # module_function: also register as class method
            if def_node.module_function
              class_methods[class_name] ||= {}
              class_methods[class_name][method_name] = serialized
            end
          rescue StandardError
            # Skip methods that fail to infer (circular deps, etc.)
            next
          end

          { instance_methods: instance_methods, class_methods: class_methods }
        end

        # Collect all DefNodes from gem files using the location index
        # @param gem_files [Array<String>] File paths belonging to this gem
        # @return [Set<IR::DefNode>] Set of DefNodes for O(1) membership check
        private def collect_def_nodes(gem_files)
          result = Set.new
          gem_files.each do |file_path|
            @location_index.nodes_for_file(file_path).each do |node|
              result << node if node.is_a?(IR::DefNode)
            end
          end
          result
        end

        private def serialize_signature(method_signature)
          {
            "return_type" => TypeSerializer.serialize(method_signature.return_type),
            "params" => method_signature.params.map do |p|
              { "name" => p.name.to_s, "kind" => p.kind.to_s, "type" => TypeSerializer.serialize(p.type) }
            end
          }
        end
      end
    end
  end
end
