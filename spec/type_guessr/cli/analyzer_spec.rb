# frozen_string_literal: true

require "tempfile"
require "type_guessr/cli/analyzer"
require "type_guessr/runtime/arity"

# Fake runtime index for analyzer specs.
#
# `defined_methods` maps a receiver key to the method names it answers:
#   "User"  → instance methods, "User." → singleton (class) methods.
# A class absent from the table is unknown to the runtime (method_defined? → nil).
#
# `reflected` maps a name to a real Ruby class or module, which then answers
# existence, arity (through the same code the server runs) and constant kind.
class FakeRuntimeIndex < InferenceHelper::StubIndexAdapter
  attr_reader :queries

  def initialize(defined_methods: {}, known_constants: [], reflected: {})
    super()
    @defined_methods = defined_methods
    @known_constants = known_constants
    @reflected = reflected
    @queries = []
  end

  def constant_kind(name)
    mod = @reflected[name]
    return mod.is_a?(Class) ? :class : :module if mod

    @known_constants.include?(name) ? :class : nil
  end

  def method_defined?(class_name, method_name, singleton: false, positional_count: nil, keywords: [])
    @queries << [class_name, method_name, singleton, positional_count, keywords]

    mod = @reflected[class_name]
    return reflect(mod, method_name, singleton, positional_count, keywords) if mod

    @defined_methods[singleton ? "#{class_name}." : class_name]&.include?(method_name)
  end

  private def reflect(mod, method_name, singleton, positional_count, keywords)
    name = method_name.to_sym
    return false unless singleton ? mod.respond_to?(name) : mod.method_defined?(name)
    return true if TypeGuessr::Runtime::Arity.accepts_arity?(mod, name, singleton, positional_count, keywords)

    "arity"
  end
end

RSpec.describe TypeGuessr::CLI::Analyzer do
  def analyze(source, code_index)
    Tempfile.create(["analyzer_spec", ".rb"]) do |f|
      f.write(source)
      f.flush
      described_class.send(
        :analyze_file,
        f.path,
        code_index: code_index,
        signature_registry: InferenceHelper.shared_signature_registry
      )
    end
  end

  describe "method-existence check on directly-typed receivers" do
    let(:source) { <<~RUBY }
      u = User.new
      u.emial
    RUBY

    it "reports a method the receiver class does not define" do
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"] })

      result = analyze(source, index)

      expect(result[:findings].size).to eq(1)
      finding = result[:findings].first
      expect(finding.name).to eq("u")
      expect(finding.inferred_type).to eq("User")
      expect(finding.reason).to include("emial")
      expect(result[:skipped]).to eq(0)
    end

    it "stays silent when the receiver class defines the method" do
      index = FakeRuntimeIndex.new(defined_methods: { "User" => %w[email emial] })

      expect(analyze(source, index)[:findings]).to be_empty
    end

    it "stays silent when the class is unknown to the runtime" do
      index = FakeRuntimeIndex.new(defined_methods: {})

      expect(analyze(source, index)[:findings]).to be_empty
    end

    it "stays silent when any union member defines the method" do
      union_source = <<~RUBY
        u = rand > 0.5 ? User.new : nil
        u.email
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"], "NilClass" => [] })

      expect(analyze(union_source, index)[:findings]).to be_empty
    end

    it "reports when no union member defines the method" do
      union_source = <<~RUBY
        u = rand > 0.5 ? User.new : nil
        u.emial
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"], "NilClass" => [] })

      findings = analyze(union_source, index)[:findings]
      expect(findings.size).to eq(1)
      expect(findings.first.reason).to include("emial")
    end

    it "queries the singleton side for a class-object receiver" do
      singleton_source = <<~RUBY
        k = User
        k.where
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User." => ["where"] }, known_constants: ["User"])

      expect(analyze(singleton_source, index)[:findings]).to be_empty
      expect(index.queries).to include(["User", "where", true, 0, []])
    end

    it "does nothing when the code index has no method_defined?" do
      index = InferenceHelper::StubIndexAdapter.new

      expect { analyze(source, index) }.not_to raise_error
      expect(analyze(source, index)[:findings]).to be_empty
    end

    it "queries each class/method pair only once" do
      repeated = <<~RUBY
        a = User.new
        a.emial
        b = User.new
        b.emial
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"] })

      result = Tempfile.create(["analyzer_spec", ".rb"]) do |f|
        f.write(repeated)
        f.flush
        described_class.analyze([f.path], code_index: index)
      end

      expect(result.findings.size).to eq(2)
      expect(index.queries).to eq([["User", "emial", false, 0, []]])
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

    it "reports a call the method cannot accept" do
      findings = analyze("u = User.new\nu.admin?(true)\n", index)[:findings]

      expect(findings.size).to eq(1)
      expect(findings.first.reason).to eq("User#admin? does not accept 1 positional argument")
    end

    it "stays silent when the arity matches" do
      expect(analyze("u = User.new\nu.admin?\n", index)[:findings]).to be_empty
      expect(analyze("u = User.new\nu.rename(\"x\")\n", index)[:findings]).to be_empty
    end

    it "stays silent when a splat hides the argument count" do
      source = <<~RUBY
        args = [1, 2]
        u = User.new
        u.admin?(*args)
      RUBY

      expect(analyze(source, index)[:findings]).to be_empty
      expect(index.queries).to include(["User", "admin?", false, nil, []])
    end

    it "counts keywords as one positional when the method takes no keywords" do
      expect(analyze("u = User.new\nu.rename(force: true)\n", index)[:findings]).to be_empty

      findings = analyze("u = User.new\nu.admin?(force: true)\n", index)[:findings]
      expect(findings.size).to eq(1)
      expect(findings.first.reason).to eq("User#admin? does not accept 0 positional arguments + keyword force:")
    end
  end

  describe "receivers that carry no judgment" do
    it "stays silent when the type is exactly nil" do
      source = <<~RUBY
        x = nil
        x.id
      RUBY
      index = FakeRuntimeIndex.new(reflected: { "NilClass" => NilClass })

      expect(analyze(source, index)[:findings]).to be_empty
    end

    it "still reports a NilClass member inside a union" do
      source = <<~RUBY
        u = rand > 0.5 ? User.new : nil
        u.emial
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"], "NilClass" => [] })

      expect(analyze(source, index)[:findings].size).to eq(1)
    end

    it "stays silent when the receiver class name is a module at runtime" do
      source = <<~RUBY
        u = User.new
        u.save!
      RUBY
      index = FakeRuntimeIndex.new(reflected: { "User" => Module.new })

      expect(analyze(source, index)[:findings]).to be_empty
    end
  end

  describe "Never findings" do
    it "still reports zero-candidate write sites" do
      never_source = <<~RUBY
        user = repo.find(1)
        user.emial
      RUBY
      index = FakeRuntimeIndex.new(defined_methods: { "User" => ["email"] })

      findings = analyze(never_source, index)[:findings]
      expect(findings.size).to eq(1)
      expect(findings.first.inferred_type).to eq("never")
    end
  end
end
