# frozen_string_literal: true

require "prism"
require_relative "../core"
require_relative "../runtime/index_adapter"

module TypeGuessr
  module CLI
    # Full inference analyzer: runs PrismConverter → IR → Resolver per file,
    # reports variables/params where type resolves to Unknown.
    module Analyzer
      Finding = Data.define(:file, :line, :name, :node_type, :inferred_type, :reason)

      # Analyze project files using the full inference engine.
      # @param files [Array<String>] absolute paths to .rb files
      # @param code_index [Object] CodeIndexAdapter-compatible object
      # @return [Array<Finding>]
      def self.analyze(files, code_index:, on_error: nil)
        signature_registry = Core::Registry::SignatureRegistry.new
        signature_registry.preload

        findings = []

        files.each do |file_path|
          file_findings = analyze_file(file_path, code_index: code_index, signature_registry: signature_registry)
          findings.concat(file_findings)
        rescue StandardError => e
          on_error&.call(file_path, e)
        end

        findings
      end

      # Analyze a single file.
      # @return [Array<Finding>]
      def self.analyze_file(file_path, code_index:, signature_registry:)
        source = File.read(file_path)
        parsed = Prism.parse(source)

        converter = Core::Converter::PrismConverter.new
        location_index = Core::Index::LocationIndex.new
        method_registry = Core::Registry::MethodRegistry.new(code_index: code_index)
        ivar_registry = Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
        cvar_registry = Core::Registry::ClassVariableRegistry.new

        context = Core::Converter::PrismConverter::Context.new(
          file_path: file_path,
          location_index: location_index,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry
        )

        parsed.value.statements&.body&.each { |stmt| converter.convert(stmt, context) }
        location_index.finalize!

        type_simplifier = Core::TypeSimplifier.new(code_index: code_index)
        resolver = Core::Inference::Resolver.new(
          signature_registry,
          code_index: code_index,
          method_registry: method_registry,
          ivar_registry: ivar_registry,
          cvar_registry: cvar_registry,
          type_simplifier: type_simplifier
        )

        collect_unknown_nodes(location_index, resolver, file_path, source)
      end

      # Collect nodes that resolve to Unknown type.
      def self.collect_unknown_nodes(location_index, resolver, file_path, source)
        findings = []
        lines = source.lines

        location_index.each_node do |node, _scope_id|
          next unless target_node?(node)

          result = resolver.infer(node)
          next unless result.type.is_a?(Core::Types::Unknown)
          # Skip ivar assignments from untyped params — expected without RBS.
          next if result.reason.include?("parameter without type info")

          line = offset_to_line(node.loc, lines)
          findings << Finding.new(
            file: file_path,
            line: line,
            name: node_name(node),
            node_type: node_type_label(node),
            inferred_type: result.type.to_s,
            reason: result.reason
          )
        rescue StandardError
          # Skip nodes that cause inference errors
        end

        findings
      end

      # Only check write nodes — the assignment target where type is determined.
      # Read nodes inherit from writes; params are expected to be Unknown without RBS.
      def self.target_node?(node)
        case node
        when Core::IR::LocalWriteNode, Core::IR::InstanceVariableWriteNode
          true
        else
          false
        end
      end

      def self.node_name(node)
        node.name.to_s
      end

      def self.node_type_label(node)
        case node
        when Core::IR::LocalWriteNode then "LocalVariable"
        when Core::IR::InstanceVariableWriteNode then "InstanceVariable"
        else node.class.name.split("::").last
        end
      end

      def self.offset_to_line(offset, lines)
        return 1 unless offset

        pos = 0
        lines.each_with_index do |line, i|
          return i + 1 if pos + line.bytesize > offset

          pos += line.bytesize
        end
        lines.size
      end

      private_class_method :analyze_file, :collect_unknown_nodes, :target_node?,
                           :node_name, :node_type_label, :offset_to_line
    end
  end
end
