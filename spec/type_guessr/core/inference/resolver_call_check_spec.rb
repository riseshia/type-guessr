# frozen_string_literal: true

require "spec_helper"

# A write whose inferred type cannot answer the methods called on it is not
# that type at all — the resolver turns it into Never, the same verdict duck
# typing gives a receiver with zero candidates.
RSpec.describe TypeGuessr::Core::Inference::Resolver, "#infer" do
  def infer_write(source, code_index, name:)
    file_path = "/tmp/call_check_spec.rb"
    converter = TypeGuessr::Core::Converter::PrismConverter.new
    location_index = TypeGuessr::Core::Index::LocationIndex.new
    method_registry = TypeGuessr::Core::Registry::MethodRegistry.new(code_index: code_index)
    ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
    cvar_registry = TypeGuessr::Core::Registry::ClassVariableRegistry.new

    context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
      file_path: file_path,
      location_index: location_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry
    )
    Prism.parse(source).value.statements&.body&.each { |stmt| converter.convert(stmt, context) }
    location_index.finalize!

    resolver = described_class.new(
      InferenceHelper.shared_signature_registry,
      type_simplifier: TypeGuessr::Core::TypeSimplifier.new(code_index: code_index),
      code_index: code_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry
    )
    write = location_index.nodes_for_file(file_path).find do |n|
      n.is_a?(TypeGuessr::Core::IR::LocalWriteNode) && n.name.to_s == name
    end
    resolver.infer(write)
  end

  let(:never) { TypeGuessr::Core::Types::Never.instance }

  describe "method existence on a directly typed write" do
    let(:source) { <<~RUBY }
      u = User.new
      u.emial
    RUBY

    it "resolves to Never when the class does not define the method" do
      result = infer_write(source, FakeRuntimeIndex.new(defined_methods: { "User" => ["email"] }), name: "u")

      expect(result.type).to be(never)
      expect(result.reason).to eq("User does not define emial")
    end

    it "keeps the type when the class defines the method" do
      result = infer_write(source, FakeRuntimeIndex.new(defined_methods: { "User" => %w[email emial] }), name: "u")

      expect(result.type.to_s).to eq("User")
    end

    it "keeps the type when the class is unknown to the runtime" do
      result = infer_write(source, FakeRuntimeIndex.new, name: "u")

      expect(result.type.to_s).to eq("User")
    end

    it "keeps the type when the code index cannot answer existence" do
      result = infer_write(source, InferenceHelper::StubIndexAdapter.new, name: "u")

      expect(result.type.to_s).to eq("User")
    end

    it "keeps a union when any member defines the method" do
      union = "u = rand > 0.5 ? User.new : nil\nu.email\n"
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"], "NilClass" => [] })

      expect(infer_write(union, index, name: "u").type).not_to be(never)
    end

    it "resolves a union to Never when no member defines the method" do
      union = "u = rand > 0.5 ? User.new : nil\nu.emial\n"
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"], "NilClass" => [] })

      result = infer_write(union, index, name: "u")
      expect(result.type).to be(never)
      expect(result.reason).to include("emial")
    end

    it "queries the singleton side for a class-object write" do
      index = FakeRuntimeIndex.new(defined_methods: { "User." => ["where"] }, known_constants: ["User"])

      expect(infer_write("k = User\nk.where\n", index, name: "k").type).not_to be(never)
      expect(index.queries).to include(["User", "where", true, 0, []])
    end
  end

  describe "call arity" do
    let(:user_class) do
      Class.new do
        def admin?; end

        def rename(name); end
      end
    end
    let(:index) { FakeRuntimeIndex.new(reflected: { "User" => user_class }) }

    it "resolves to Never when the method cannot accept the call" do
      result = infer_write("u = User.new\nu.admin?(true)\n", index, name: "u")

      expect(result.type).to be(never)
      expect(result.reason).to eq("User#admin? does not accept 1 positional argument")
    end

    it "keeps the type when the arity matches" do
      expect(infer_write("u = User.new\nu.admin?\n", index, name: "u").type.to_s).to eq("User")
      expect(infer_write("u = User.new\nu.rename(\"x\")\n", index, name: "u").type.to_s).to eq("User")
    end

    it "keeps the type when a splat hides the argument count" do
      source = "args = [1, 2]\nu = User.new\nu.admin?(*args)\n"

      expect(infer_write(source, index, name: "u").type.to_s).to eq("User")
      expect(index.queries).to include(["User", "admin?", false, nil, []])
    end

    it "counts keywords as one positional when the method takes no keywords" do
      expect(infer_write("u = User.new\nu.rename(force: true)\n", index, name: "u").type.to_s).to eq("User")

      result = infer_write("u = User.new\nu.admin?(force: true)\n", index, name: "u")
      expect(result.reason).to eq("User#admin? does not accept 0 positional arguments + keyword force:")
    end

    it "checks arity on a duck-typed write too" do
      duck_index = Class.new(FakeRuntimeIndex) do
        def find_classes_defining_methods(_called_methods) = ["User"]
      end.new(reflected: { "User" => user_class })

      result = infer_write("u = repo.find(1)\nu.admin?(true)\n", duck_index, name: "u")
      expect(result.type).to be(never)
      expect(result.reason).to include("does not accept 1 positional argument")
    end
  end

  describe "receivers that carry no judgment" do
    it "keeps a bare nil type" do
      result = infer_write("x = nil\nx.id\n", FakeRuntimeIndex.new(reflected: { "NilClass" => NilClass }), name: "x")

      expect(result.type.to_s).to eq("nil")
    end

    it "keeps the type when the receiver class name is a module at runtime" do
      result = infer_write("u = User.new\nu.save!\n", FakeRuntimeIndex.new(reflected: { "User" => Module.new }), name: "u")

      expect(result.type.to_s).to eq("User")
    end
  end
end
