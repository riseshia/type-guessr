# frozen_string_literal: true

require "bundler/setup"
require "rspec"

# Load TypeGuessr core components
require_relative "../../lib/type_guessr/core/index/location_index"
require_relative "../../lib/type_guessr/core/inference/resolver"
require_relative "../../lib/type_guessr/core/registry/method_registry"
require_relative "../../lib/type_guessr/core/signature_provider"
require_relative "../../lib/type_guessr/core/ir/nodes"
require_relative "../../lib/type_guessr/core/types"
require_relative "../lib/coverage_report"

RSpec.describe CoverageRunner::CoverageReport do
  let(:location_index) { TypeGuessr::Core::Index::LocationIndex.new }
  let(:provider) { TypeGuessr::Core::SignatureProvider.new }
  let(:method_registry) { TypeGuessr::Core::Registry::MethodRegistry.new }
  let(:resolver) { TypeGuessr::Core::Inference::Resolver.new(provider, method_registry: method_registry) }
  let(:report) { described_class.new(location_index, resolver, method_registry) }

  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  def make_literal_node(type, offset:)
    TypeGuessr::Core::IR::LiteralNode.new(
      type: type,
      literal_value: nil,
      values: nil,
      loc: TypeGuessr::Core::IR::Loc.new(offset: offset)
    )
  end

  def make_param_node(name, offset:, called_methods: [])
    TypeGuessr::Core::IR::ParamNode.new(
      name: name,
      kind: :required,
      default_value: nil,
      called_methods: called_methods,
      loc: TypeGuessr::Core::IR::Loc.new(offset: offset)
    )
  end

  def make_local_write_node(name, value, offset:)
    TypeGuessr::Core::IR::LocalWriteNode.new(
      name: name,
      value: value,
      called_methods: [],
      loc: TypeGuessr::Core::IR::Loc.new(offset: offset)
    )
  end

  def make_def_node(name, params, return_node, offset:)
    TypeGuessr::Core::IR::DefNode.new(
      name: name,
      class_name: "TestClass",
      params: params,
      return_node: return_node,
      body_nodes: [],
      loc: TypeGuessr::Core::IR::Loc.new(offset: offset),
      singleton: false
    )
  end

  describe "#generate" do
    it "returns a hash with node_coverage and signature_score" do
      result = report.generate
      expect(result).to have_key(:node_coverage)
      expect(result).to have_key(:signature_score)
    end
  end

  describe "node coverage" do
    it "calculates coverage excluding DefNode" do
      # LiteralNode - typed (String)
      literal_node = make_literal_node(string_type, offset: 1)
      location_index.add("/test.rb", literal_node, "")

      # ParamNode - untyped (no default, no called_methods)
      param_node = make_param_node(:x, offset: 2)
      location_index.add("/test.rb", param_node, "")

      # DefNode - should be excluded from count
      def_node = make_def_node(:foo, [param_node], literal_node, offset: 3)
      location_index.add("/test.rb", def_node, "TestClass")

      result = report.generate
      coverage = result[:node_coverage]

      # Only LiteralNode and ParamNode should be counted (DefNode excluded)
      expect(coverage[:total]).to eq(2)
      expect(coverage[:typed]).to eq(1) # only LiteralNode is typed
      expect(coverage[:percentage]).to be_within(0.1).of(50.0)
    end

    it "provides breakdown by node type" do
      literal1 = make_literal_node(string_type, offset: 1)
      literal2 = make_literal_node(integer_type, offset: 2)
      param1 = make_param_node(:x, offset: 3)

      location_index.add("/test.rb", literal1, "")
      location_index.add("/test.rb", literal2, "")
      location_index.add("/test.rb", param1, "")

      result = report.generate
      breakdown = result[:node_coverage][:breakdown]

      expect(breakdown).to have_key("LiteralNode")
      expect(breakdown["LiteralNode"][:total]).to eq(2)
      expect(breakdown["LiteralNode"][:typed]).to eq(2)

      expect(breakdown).to have_key("ParamNode")
      expect(breakdown["ParamNode"][:total]).to eq(1)
      expect(breakdown["ParamNode"][:typed]).to eq(0)
    end

    it "returns zero coverage when no nodes" do
      result = report.generate
      coverage = result[:node_coverage]

      expect(coverage[:total]).to eq(0)
      expect(coverage[:typed]).to eq(0)
      expect(coverage[:percentage]).to eq(0.0)
    end
  end

  describe "signature score" do
    it "calculates average slot coverage for project methods" do
      # Method with typed return, untyped param
      # Slots: 1 param + 1 return = 2 slots
      # Typed: 0 param + 1 return = 1 typed
      # Score: 1/2 = 0.5
      param = make_param_node(:x, offset: 1)
      return_value = make_literal_node(string_type, offset: 2)
      def_node = make_def_node(:method1, [param], return_value, offset: 3)

      method_registry.register("TestClass", "method1", def_node)
      location_index.add("/test.rb", def_node, "TestClass")
      location_index.add("/test.rb", param, "TestClass#method1")
      location_index.add("/test.rb", return_value, "TestClass#method1")

      result = report.generate
      sig_score = result[:signature_score]

      expect(sig_score[:method_count]).to eq(1)
      expect(sig_score[:average_score]).to be_within(0.01).of(0.5)
    end

    it "calculates correct score with all typed slots" do
      # Method with typed param (has default) and typed return
      # Slots: 1 param + 1 return = 2 slots, all typed
      default_value = make_literal_node(integer_type, offset: 1)
      param = TypeGuessr::Core::IR::ParamNode.new(
        name: :x,
        kind: :optional,
        default_value: default_value,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(offset: 2, col_range: 0...5)
      )
      return_value = make_literal_node(string_type, offset: 3)
      def_node = make_def_node(:method2, [param], return_value, offset: 4)

      method_registry.register("TestClass", "method2", def_node)
      location_index.add("/test.rb", def_node, "TestClass")
      location_index.add("/test.rb", default_value, "TestClass#method2")
      location_index.add("/test.rb", param, "TestClass#method2")
      location_index.add("/test.rb", return_value, "TestClass#method2")

      result = report.generate
      sig_score = result[:signature_score]

      expect(sig_score[:average_score]).to be_within(0.01).of(1.0)
    end

    it "returns zero score when no methods" do
      result = report.generate
      sig_score = result[:signature_score]

      expect(sig_score[:method_count]).to eq(0)
      expect(sig_score[:average_score]).to eq(0.0)
    end

    it "handles methods without return value (returns nil)" do
      # Method with no return value (empty body) - treated as NilClass return
      param = make_param_node(:x, offset: 1)
      def_node = TypeGuessr::Core::IR::DefNode.new(
        name: :method3,
        class_name: "TestClass",
        params: [param],
        return_node: nil,
        body_nodes: [],
        loc: TypeGuessr::Core::IR::Loc.new(offset: 2, col_range: 0...5),
        singleton: false
      )

      method_registry.register("TestClass", "method3", def_node)
      location_index.add("/test.rb", def_node, "TestClass")
      location_index.add("/test.rb", param, "TestClass#method3")

      result = report.generate
      sig_score = result[:signature_score]

      # nil return is typed (NilClass), param is untyped
      # Score: 1/2 = 0.5
      expect(sig_score[:average_score]).to be_within(0.01).of(0.5)
    end
  end
end
