# frozen_string_literal: true

# Lightweight type inference helper for tests.
# Runs the full TypeGuessr pipeline (parse → IR → resolve) using a
# stub index adapter (no subprocess needed).
module InferenceHelper
  # Minimal stub that satisfies the CodeIndexAdapter interface for tests.
  # Does not resolve duck-typing or ancestors — tests that need those
  # should use a RuntimeIndexAdapter with a real subprocess.
  class StubIndexAdapter
    def build_member_index!; end
    def refresh_member_index!(_file_uri = nil); end
    def member_entries_for_file(_file_path) = []
    def find_classes_defining_methods(_called_methods) = []
    def ancestors_of(_class_name) = []
    def constant_kind(_name) = nil
    def class_method_owner(_class_name, _method_name) = nil
    def instance_method_owner(_class_name, _method_name) = nil
    def resolve_constant_name(_short_name, _nesting) = nil
    def method_definition_file_path(_class_name, _method_name, singleton: false) = nil
    def register_method_class(_class_name, _method_name) = nil
    def unregister_method_classes(_class_name) = nil
  end

  class << self
    def shared_signature_registry
      @shared_signature_registry ||= begin
        registry = TypeGuessr::Core::Registry::SignatureRegistry.new
        registry.preload
        registry
      end
    end
  end

  # Assert that type inference at the given position matches expected type string.
  def expect_inferred_type(line:, column:, expected:)
    record_inference_for_doc(line: line, column: column, expected: expected)

    actual = infer_type_at(source, line: line, column: column)
    expect(actual).to eq(expected),
                      "Expected type '#{expected}' but got '#{actual}'"
  end

  # Assert that type inference at the given position does NOT include any of the given types.
  def expect_inferred_type_excludes(line:, column:, types:)
    actual = infer_type_at(source, line: line, column: column)
    types.each do |type|
      expect(actual).not_to include(type),
                            "Expected type NOT to include '#{type}', got '#{actual}'"
    end
  end

  # Assert that method signature at the given position matches expected signature string.
  def expect_inferred_signature(line:, column:, expected_signature:)
    record_inference_for_doc_signature(line: line, column: column, expected_signature: expected_signature)

    pipeline = build_pipeline(source)
    target_offset = line_column_to_offset(source, line, column)
    node = find_node_at_offset(pipeline[:location_index], pipeline[:file_path], target_offset)

    raise "No IR node found at line #{line}, column #{column}" unless node

    sig_builder = TypeGuessr::Core::SignatureBuilder.new(pipeline[:resolver])

    signature = case node
                when TypeGuessr::Core::IR::DefNode
                  sig_builder.build_from_def_node(node)
                when TypeGuessr::Core::IR::CallNode
                  build_call_signature(node, pipeline)
                else
                  raise "Cannot build signature for #{node.class} at line #{line}, column #{column}"
                end

    expect(signature.to_s).to include(expected_signature),
                              "Expected signature to include '#{expected_signature}', got '#{signature}'"
  end

  # Infer type at a given line/column in source code.
  def infer_type_at(source, line:, column:)
    result = infer_result_at(source, line: line, column: column)
    result.type.to_s
  end

  # Get full inference result at a given line/column.
  def infer_result_at(source, line:, column:)
    pipeline = build_pipeline(source)
    target_offset = line_column_to_offset(source, line, column)
    node = find_node_at_offset(pipeline[:location_index], pipeline[:file_path], target_offset)

    raise "No IR node found at line #{line}, column #{column} (offset #{target_offset})" unless node

    pipeline[:resolver].infer(node)
  end

  private def build_pipeline(source)
    file_path = "/tmp/inference_test.rb"

    code_index = StubIndexAdapter.new

    converter = TypeGuessr::Core::Converter::PrismConverter.new
    location_index = TypeGuessr::Core::Index::LocationIndex.new
    method_registry = TypeGuessr::Core::Registry::MethodRegistry.new(code_index: code_index)
    ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
    cvar_registry = TypeGuessr::Core::Registry::ClassVariableRegistry.new

    parsed = Prism.parse(source)
    context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
      file_path: file_path,
      location_index: location_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry
    )
    parsed.value.statements&.body&.each { |stmt| converter.convert(stmt, context) }
    location_index.finalize!

    type_simplifier = TypeGuessr::Core::TypeSimplifier.new(code_index: code_index)
    resolver = TypeGuessr::Core::Inference::Resolver.new(
      InferenceHelper.shared_signature_registry,
      code_index: code_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry,
      type_simplifier: type_simplifier
    )

    { resolver: resolver, location_index: location_index, method_registry: method_registry,
      code_index: code_index, file_path: file_path }
  end

  private def build_call_signature(call_node, pipeline)
    method_name = call_node.method.to_s

    if method_name == "new" && call_node.receiver
      class_result = pipeline[:resolver].infer(call_node.receiver)
      class_name = class_result.type.respond_to?(:name) ? class_result.type.name : class_result.type.to_s
      def_node = pipeline[:method_registry].lookup(class_name, "initialize")

      sig_builder = TypeGuessr::Core::SignatureBuilder.new(pipeline[:resolver])
      if def_node
        sig = sig_builder.build_from_def_node(def_node)
        return TypeGuessr::Core::Types::MethodSignature.new(
          sig.params, TypeGuessr::Core::Types::ClassInstance.new(class_name)
        )
      end

      return TypeGuessr::Core::Types::MethodSignature.new(
        [], TypeGuessr::Core::Types::ClassInstance.new(class_name)
      )
    end

    raise "Cannot build signature for call to #{method_name}"
  end

  private def line_column_to_offset(source, line, column)
    lines = source.lines
    offset = 0
    (line - 1).times do |i|
      offset += (lines[i] || "").bytesize
    end
    offset + column
  end

  private def find_node_at_offset(location_index, file_path, target_offset)
    nodes = location_index.nodes_for_file(file_path)
    exact = nodes.find { |n| n.loc == target_offset }
    return exact if exact

    candidates = nodes.select { |n| n.loc && n.loc <= target_offset }
    candidates.max_by(&:loc)
  end

  private def record_inference_for_doc(line:, column:, expected:)
    return unless defined?(DocCollector) && defined?(RSpec)

    example = RSpec.current_example
    return unless example&.metadata&.dig(:doc)

    group_hierarchy = extract_inference_group_hierarchy(example)

    DocCollector.record(
      source: source,
      line: line,
      column: column,
      expected: expected,
      group_hierarchy: group_hierarchy,
      description: example.description,
      spec_file: example.metadata[:file_path]
    )
  end

  private def record_inference_for_doc_signature(line:, column:, expected_signature:)
    return unless defined?(DocCollector) && defined?(RSpec)

    example = RSpec.current_example
    return unless example&.metadata&.dig(:doc)

    group_hierarchy = extract_inference_group_hierarchy(example)

    DocCollector.record_method_signature(
      source: source,
      line: line,
      column: column,
      expected_signature: expected_signature,
      group_hierarchy: group_hierarchy,
      description: example.description,
      spec_file: example.metadata[:file_path]
    )
  end

  private def extract_inference_group_hierarchy(example)
    hierarchy = []
    current = example.metadata[:example_group]
    found_doc_tag = false

    while current
      found_doc_tag = true if current[:doc]
      hierarchy.unshift(current[:description]) if found_doc_tag && current[:description] && !current[:description].empty?
      current = current[:parent_example_group]
    end

    hierarchy.shift if hierarchy.size > 2
    hierarchy
  end
end

RSpec.configure do |config|
  config.include InferenceHelper
end
