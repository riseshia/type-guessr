# frozen_string_literal: true

require "prism"
require_relative "../core"
require_relative "../runtime/index_adapter"

module TypeGuessr
  module CLI
    # Full inference analyzer: runs PrismConverter → IR → Resolver per file,
    # reports variables/params where type resolves to Never (zero candidates).
    # Unknown (type inference gap) is not reported — only Never (no valid type exists).
    # Directly-typed sites (e.g. `u = User.new`) can never resolve to Never, so
    # their called methods are instead existence-checked one by one against the
    # runtime index.
    module Analyzer
      Finding = Data.define(:file, :line, :name, :node_type, :inferred_type, :reason)
      Result = Data.define(:findings, :skipped_count)

      # Analyze project files using the full inference engine.
      # @param files [Array<String>] absolute paths to .rb files
      # @param code_index [Object] CodeIndexAdapter-compatible object
      # @return [Result]
      def self.analyze(files, code_index:, on_error: nil)
        signature_registry = Core::Registry::SignatureRegistry.new
        signature_registry.preload

        findings = []
        skipped_count = 0
        method_cache = {}

        files.each do |file_path|
          file_result = analyze_file(file_path, code_index: code_index, signature_registry: signature_registry,
                                                method_cache: method_cache)
          findings.concat(file_result[:findings])
          skipped_count += file_result[:skipped]
        rescue Runtime::Client::ServerDiedError
          raise
        rescue StandardError => e
          on_error&.call(file_path, e)
        end

        Result.new(findings: findings, skipped_count: skipped_count)
      end

      # Analyze a single file.
      # @return [Array<Finding>]
      def self.analyze_file(file_path, code_index:, signature_registry:, method_cache: {})
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

        collect_never_nodes(location_index, resolver, file_path, source,
                            code_index: code_index, method_cache: method_cache)
      end

      # Collect nodes that resolve to Never type (zero candidates), plus
      # directly-typed nodes calling a method their type does not define.
      # Unknown (inference gap) is skipped — only Never (no valid type exists) is reported.
      def self.collect_never_nodes(location_index, resolver, file_path, source, code_index: nil, method_cache: {})
        findings = []
        skipped = 0
        lines = source.lines

        location_index.each_node do |node, _scope_id|
          next unless target_node?(node)

          result = resolver.infer(node)
          missing = missing_methods_for(node, result, code_index, method_cache)

          dump_surface_site(node, result, file_path, lines)
          dump_coverage_site(node, result, file_path, lines, missing)

          if result.type.is_a?(Core::Types::Never)
            line = offset_to_line(node.loc, lines)
            findings << Finding.new(
              file: file_path,
              line: line,
              name: node_name(node),
              node_type: node_type_label(node),
              inferred_type: result.type.to_s,
              reason: result.reason
            )
          elsif result.type.is_a?(Core::Types::Unknown)
            skipped += 1
          elsif missing.any?
            findings << Finding.new(
              file: file_path,
              line: offset_to_line(node.loc, lines),
              name: node_name(node),
              node_type: node_type_label(node),
              inferred_type: result.type.to_s,
              reason: missing_reason(result.type, missing)
            )
          end
        rescue Runtime::Client::ServerDiedError
          raise
        rescue StandardError
          # Skip nodes that cause inference errors
        end

        { findings: findings, skipped: skipped }
      end

      # Methods called on a node whose type is already known, but which that
      # type cannot answer. Empty unless the code index can answer method
      # existence (only the runtime index can — the static one cannot).
      # @return [Array<Array(Core::IR::CalledMethod, Symbol)>] [call, :missing | :arity]
      def self.missing_methods_for(node, result, code_index, cache)
        return [] if result.type.is_a?(Core::Types::Never) || result.type.is_a?(Core::Types::Unknown)
        return [] unless code_index.respond_to?(:method_defined?)
        return [] unless node.respond_to?(:called_methods) && node.called_methods.any?

        missing_methods(result.type, node.called_methods, code_index, cache)
      end

      def self.missing_methods(type, called_methods, code_index, cache)
        # A bare `nil` type comes from `x = nil` before a loop fills x in;
        # flow-insensitive analysis attaches the later calls to that write, so
        # it says nothing about the real receiver.
        return [] if nil_type?(type)

        receivers = expand_receivers(type)
        return [] if receivers.nil? || receivers.empty?

        seen = {}
        called_methods.filter_map do |cm|
          signature = call_signature(cm)
          next if seen[signature]

          seen[signature] = true

          answers = receivers.map { |class_name, singleton| receiver_answer(class_name, singleton, signature, code_index, cache) }
          # nil = class unknown to the index, true = callable: not evidence of absence.
          next if answers.any? { |a| a.nil? || a == true }

          [cm, answers.all? { |a| a == "arity" } ? :arity : :missing]
        end
      end

      # @return [Array(String, Integer?, Array<String>)] name, positional count, keywords
      def self.call_signature(called_method)
        [called_method.name.to_s, called_method.positional_count, (called_method.keywords || []).map(&:to_s)]
      end

      def self.receiver_answer(class_name, singleton, signature, code_index, cache)
        # A value cannot be an instance of a module, so an instance-level module
        # receiver means the inferred type is wrong — answer "unknown".
        # `MyModule.helper` is a real call, so singleton receivers stay checkable.
        return nil if !singleton && constant_kind(class_name, code_index, cache) == :module

        method_name, positional_count, keywords = signature
        key = [class_name, method_name, singleton, positional_count, keywords]
        cache.fetch(key) do
          cache[key] = code_index.method_defined?(class_name, method_name, singleton: singleton,
                                                                           positional_count: positional_count,
                                                                           keywords: keywords)
        end
      end

      def self.constant_kind(class_name, code_index, cache)
        return nil unless code_index.respond_to?(:constant_kind)

        key = [:constant_kind, class_name]
        cache.fetch(key) { cache[key] = code_index.constant_kind(class_name) }
      end

      # True when the type is exactly `nil` — a NilClass member inside a Union
      # still answers normally.
      def self.nil_type?(type)
        type.is_a?(Core::Types::ClassInstance) && type.name == "NilClass"
      end

      # Flatten a type into the receivers a call would dispatch on.
      # @return [Array<Array(String, Boolean)>, nil] [class_name, singleton] pairs,
      #   or nil if any part of the type has no class to check against
      def self.expand_receivers(type)
        case type
        when Core::Types::Union
          type.types.each_with_object([]) do |member, acc|
            sub = expand_receivers(member)
            return nil unless sub

            acc.concat(sub)
          end
        when Core::Types::SingletonType
          [[type.name, true]]
        else
          class_name = type.rbs_class_name
          class_name ? [[class_name, false]] : nil
        end
      end

      # Human-readable reason for a directly-typed receiver that cannot answer
      # its calls. Absent methods and arity mismatches read differently.
      def self.missing_reason(type, missing)
        absent = missing.filter_map { |cm, cause| cm.name.to_s if cause == :missing }.uniq
        parts = []
        parts << "#{type} does not define #{absent.join(", ")}" if absent.any?
        missing.each do |cm, cause|
          parts << "#{type}##{cm.name} does not accept #{describe_call_args(cm)}" if cause == :arity
        end
        parts.join("; ")
      end

      def self.describe_call_args(called_method)
        parts = []
        count = called_method.positional_count
        parts << "#{count} positional argument#{"s" unless count == 1}" if count
        keywords = (called_method.keywords || []).map(&:to_s)
        parts << "keyword#{"s" if keywords.size > 1} #{keywords.map { |k| "#{k}:" }.join(", ")}" if keywords.any?
        parts.empty? ? "these arguments" : parts.join(" + ")
      end

      # Dump sites where the type was resolved via called-methods duck typing
      # (candidates >= 1) — the exact surface where a call-site mutation can
      # flip the result to Never. Used by the recall experiment to pick seed
      # sites; enabled only via TG_SURFACE_DUMP=<path> (JSONL, appended).
      def self.dump_surface_site(node, result, file_path, lines)
        dump_path = ENV.fetch("TG_SURFACE_DUMP", nil)
        return unless dump_path
        return if result.type.is_a?(Core::Types::Never) || result.type.is_a?(Core::Types::Unknown)
        return unless result.reason.to_s.include?("inferred from")

        require "json"
        entry = {
          file: file_path,
          line: offset_to_line(node.loc, lines),
          name: node_name(node),
          node_type: node_type_label(node),
          type: result.type.to_s,
          reason: result.reason,
          called_methods: (node.called_methods.map { |cm| cm.name.to_s } if node.respond_to?(:called_methods))
        }
        File.open(dump_path, "a") { |f| f.puts JSON.generate(entry) }
      end

      # Dump ALL examined write sites with their judgment category, to measure
      # how much of the surface each outcome covers (coverage experiment).
      # Categories: never / unknown (no judgment) / duck_typed / direct /
      # direct_missing (directly typed, method-existence check fired).
      # Enabled only via TG_COVERAGE_DUMP=<path> (JSONL, appended).
      def self.dump_coverage_site(node, result, file_path, lines, missing)
        dump_path = ENV.fetch("TG_COVERAGE_DUMP", nil)
        return unless dump_path

        category =
          if result.type.is_a?(Core::Types::Never) then "never"
          elsif result.type.is_a?(Core::Types::Unknown) then "unknown"
          elsif result.reason.to_s.include?("inferred from") then "duck_typed"
          elsif missing.any? then "direct_missing"
          else
            "direct"
          end

        called = node.respond_to?(:called_methods) ? node.called_methods.map { |cm| cm.name.to_s } : []

        require "json"
        entry = {
          file: file_path,
          line: offset_to_line(node.loc, lines),
          name: node_name(node),
          node_type: node_type_label(node),
          category: category,
          type: result.type.to_s,
          called_methods_count: called.size,
          called_methods: called
        }
        File.open(dump_path, "a") { |f| f.puts JSON.generate(entry) }
      end

      # Only check write nodes — the assignment target where type is determined.
      # Write nodes now use called_methods fallback, so Never is detected here.
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

      private_class_method :analyze_file, :collect_never_nodes, :target_node?,
                           :node_name, :node_type_label, :offset_to_line,
                           :dump_surface_site, :dump_coverage_site,
                           :missing_methods_for, :missing_methods, :expand_receivers,
                           :call_signature, :receiver_answer, :constant_kind, :nil_type?,
                           :missing_reason, :describe_call_args
    end
  end
end
