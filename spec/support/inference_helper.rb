# frozen_string_literal: true

# Lightweight type inference helper for tests.
# Runs the full TypeGuessr pipeline (parse → IR → resolve) WITHOUT an LSP server.
# Uses a standalone RubyIndexer::Index for duck-typing support.
module InferenceHelper
  class << self
    def shared_signature_registry
      @shared_signature_registry ||= TypeGuessr::Core::Registry::SignatureRegistry.instance
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

    index = RubyIndexer::Index.new
    uri = URI::Generic.build(scheme: "file", path: file_path)
    index.index_single(uri, source)

    code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(index)
    code_index.build_member_index!

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
    # Resolve receiver type to find the target method's DefNode
    method_name = call_node.method.to_s

    # For .new calls, look up initialize
    if method_name == "new" && call_node.receiver
      class_result = pipeline[:resolver].infer(call_node.receiver)
      class_name = class_result.type.respond_to?(:name) ? class_result.type.name : class_result.type.to_s
      def_node = pipeline[:method_registry].lookup(class_name, "initialize")

      sig_builder = TypeGuessr::Core::SignatureBuilder.new(pipeline[:resolver])
      if def_node
        sig = sig_builder.build_from_def_node(def_node)
        # Replace return type with the class instance type
        return TypeGuessr::Core::Types::MethodSignature.new(
          sig.params, TypeGuessr::Core::Types::ClassInstance.new(class_name)
        )
      end

      # No initialize → () -> ClassName
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
