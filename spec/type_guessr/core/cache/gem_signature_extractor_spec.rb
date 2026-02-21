# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/cache/gem_signature_extractor"
require "type_guessr/core/signature_builder"
require "type_guessr/core/registry/method_registry"
require "type_guessr/core/index/location_index"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::Cache::GemSignatureExtractor do
  let(:resolver) { instance_double(TypeGuessr::Core::Inference::Resolver) }
  let(:signature_builder) { TypeGuessr::Core::SignatureBuilder.new(resolver) }
  let(:method_registry) { TypeGuessr::Core::Registry::MethodRegistry.new }
  let(:location_index) { TypeGuessr::Core::Index::LocationIndex.new }

  let(:extractor) do
    described_class.new(
      signature_builder: signature_builder,
      method_registry: method_registry,
      location_index: location_index
    )
  end

  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.for("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.for("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  def make_param(name:, kind: :required, loc: nil)
    TypeGuessr::Core::IR::ParamNode.new(name, kind, nil, [], loc)
  end

  def make_def_node(name:, class_name: nil, params: [], loc: nil, singleton: false)
    TypeGuessr::Core::IR::DefNode.new(name, class_name, params, nil, [], [], loc, singleton)
  end

  def infer_result(type)
    TypeGuessr::Core::Inference::Result.new(type, "test", :test)
  end

  def register_method(file_path, class_name, method_name, def_node, scope_id: "")
    method_registry.register(class_name, method_name, def_node)
    location_index.add(file_path, def_node, scope_id)
  end

  describe "#extract" do
    it "extracts instance method signatures from gem files" do
      def_node = make_def_node(name: :greet, class_name: "Greeter", loc: 100)
      register_method("/gems/greeter-1.0.0/lib/greeter.rb", "Greeter", "greet", def_node, scope_id: "Greeter")

      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(string_type))

      result = extractor.extract(["/gems/greeter-1.0.0/lib/greeter.rb"])

      expect(result[:instance_methods]).to have_key("Greeter")
      expect(result[:instance_methods]["Greeter"]).to have_key("greet")
      expect(result[:instance_methods]["Greeter"]["greet"]["return_type"]).to eq(
        { "_type" => "ClassInstance", "name" => "String" }
      )
      expect(result[:class_methods]).to be_empty
    end

    it "extracts class method signatures (singleton methods)" do
      def_node = make_def_node(name: :build, class_name: "Factory", loc: 200, singleton: true)
      register_method("/gems/factory-1.0.0/lib/factory.rb", "Factory", "build", def_node, scope_id: "Factory")

      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(integer_type))

      result = extractor.extract(["/gems/factory-1.0.0/lib/factory.rb"])

      expect(result[:class_methods]).to have_key("Factory")
      expect(result[:class_methods]["Factory"]).to have_key("build")
      expect(result[:instance_methods]).to be_empty
    end

    it "extracts parameter types" do
      param = make_param(name: :name, kind: :required, loc: 110)
      def_node = make_def_node(name: :greet, class_name: "Greeter", params: [param], loc: 100)
      register_method("/gems/greeter-1.0.0/lib/greeter.rb", "Greeter", "greet", def_node, scope_id: "Greeter")

      allow(resolver).to receive(:infer).with(param).and_return(infer_result(string_type))
      allow(resolver).to receive(:infer).with(def_node).and_return(infer_result(string_type))

      result = extractor.extract(["/gems/greeter-1.0.0/lib/greeter.rb"])

      params = result[:instance_methods]["Greeter"]["greet"]["params"]
      expect(params.size).to eq(1)
      expect(params.first["name"]).to eq("name")
      expect(params.first["kind"]).to eq("required")
      expect(params.first["type"]).to eq({ "_type" => "ClassInstance", "name" => "String" })
    end

    it "excludes methods from non-gem files" do
      gem_def = make_def_node(name: :gem_method, class_name: "GemClass", loc: 100)
      project_def = make_def_node(name: :project_method, class_name: "ProjectClass", loc: 200)

      register_method("/gems/mygem-1.0.0/lib/mygem.rb", "GemClass", "gem_method", gem_def, scope_id: "GemClass")
      register_method("/home/user/project/app/models/user.rb", "ProjectClass", "project_method", project_def,
                      scope_id: "ProjectClass")

      allow(resolver).to receive(:infer).with(gem_def).and_return(infer_result(string_type))

      result = extractor.extract(["/gems/mygem-1.0.0/lib/mygem.rb"])

      expect(result[:instance_methods]).to have_key("GemClass")
      expect(result[:instance_methods]).not_to have_key("ProjectClass")
    end

    it "handles methods that fail to infer" do
      good_def = make_def_node(name: :good_method, class_name: "MyClass", loc: 100)
      bad_def = make_def_node(name: :bad_method, class_name: "MyClass", loc: 200)

      register_method("/gems/mygem-1.0.0/lib/mygem.rb", "MyClass", "good_method", good_def, scope_id: "MyClass")
      register_method("/gems/mygem-1.0.0/lib/mygem.rb", "MyClass", "bad_method", bad_def, scope_id: "MyClass")

      allow(resolver).to receive(:infer).with(good_def).and_return(infer_result(string_type))
      allow(resolver).to receive(:infer).with(bad_def).and_raise(StandardError, "circular dependency")

      result = extractor.extract(["/gems/mygem-1.0.0/lib/mygem.rb"])

      expect(result[:instance_methods]["MyClass"]).to have_key("good_method")
      expect(result[:instance_methods]["MyClass"]).not_to have_key("bad_method")
    end

    it "returns empty result for empty file list" do
      result = extractor.extract([])

      expect(result[:instance_methods]).to be_empty
      expect(result[:class_methods]).to be_empty
    end

    it "extracts methods from multiple files" do
      def1 = make_def_node(name: :method_a, class_name: "ClassA", loc: 100)
      def2 = make_def_node(name: :method_b, class_name: "ClassB", loc: 200)

      register_method("/gems/mygem-1.0.0/lib/class_a.rb", "ClassA", "method_a", def1, scope_id: "ClassA")
      register_method("/gems/mygem-1.0.0/lib/class_b.rb", "ClassB", "method_b", def2, scope_id: "ClassB")

      allow(resolver).to receive(:infer).with(def1).and_return(infer_result(string_type))
      allow(resolver).to receive(:infer).with(def2).and_return(infer_result(integer_type))

      result = extractor.extract([
                                   "/gems/mygem-1.0.0/lib/class_a.rb",
                                   "/gems/mygem-1.0.0/lib/class_b.rb",
                                 ])

      expect(result[:instance_methods].keys).to contain_exactly("ClassA", "ClassB")
    end
  end
end
