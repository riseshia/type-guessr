# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/signature_builder"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::SignatureBuilder do
  let(:resolver) { instance_double(TypeGuessr::Core::Inference::Resolver) }
  let(:builder) { described_class.new(resolver) }

  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  def make_param(name:, kind: :required)
    TypeGuessr::Core::IR::ParamNode.new(name, kind, nil, [], nil)
  end

  def make_def_node(name:, params: [])
    TypeGuessr::Core::IR::DefNode.new(name, nil, params, nil, [], [], nil, false)
  end

  def infer_result(type)
    TypeGuessr::Core::Inference::Result.new(type, "test", :test)
  end

  describe "#build_from_def_node" do
    it "builds signature with no params" do
      def_node = make_def_node(name: :greet)
      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(string_type))

      result = builder.build_from_def_node(def_node)

      expect(result).to be_a(TypeGuessr::Core::Types::MethodSignature)
      expect(result.params).to be_empty
      expect(result.return_type).to eq(string_type)
      expect(result.to_s).to eq("() -> String")
    end

    it "builds signature with a single required param" do
      param = make_param(name: :name)
      def_node = make_def_node(name: :greet, params: [param])

      allow(resolver).to receive(:infer).with(param).and_return(infer_result(string_type))
      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(integer_type))

      result = builder.build_from_def_node(def_node)

      expect(result.params.size).to eq(1)
      expect(result.params.first.name).to eq(:name)
      expect(result.params.first.kind).to eq(:required)
      expect(result.params.first.type).to eq(string_type)
      expect(result.return_type).to eq(integer_type)
      expect(result.to_s).to eq("(String name) -> Integer")
    end

    it "builds signature with mixed param kinds" do
      req_param = make_param(name: :name, kind: :required)
      opt_param = make_param(name: :count, kind: :optional)
      kw_param = make_param(name: :verbose, kind: :keyword_optional)
      def_node = make_def_node(name: :process, params: [req_param, opt_param, kw_param])

      allow(resolver).to receive(:infer).with(req_param).and_return(infer_result(string_type))
      allow(resolver).to receive(:infer).with(opt_param).and_return(infer_result(integer_type))
      allow(resolver).to receive(:infer).with(kw_param).and_return(infer_result(unknown_type))
      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(unknown_type))

      result = builder.build_from_def_node(def_node)

      expect(result.params.size).to eq(3)
      expect(result.to_s).to eq("(String name, ?Integer count, verbose: ?untyped) -> untyped")
    end

    it "builds signature with forwarding param" do
      fwd_param = make_param(name: :"...", kind: :forwarding)
      def_node = make_def_node(name: :delegate, params: [fwd_param])

      allow(resolver).to receive(:infer).with(fwd_param).and_return(infer_result(unknown_type))
      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(unknown_type))

      result = builder.build_from_def_node(def_node)

      expect(result.params.size).to eq(1)
      expect(result.to_s).to eq("(...) -> untyped")
    end
  end
end
