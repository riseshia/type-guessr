# frozen_string_literal: true

require "tempfile"
require "type_guessr/cli/analyzer"

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

  let(:index) { FakeRuntimeIndex.new(defined_methods: { "User" => ["email"] }) }

  it "reports write sites the resolver turns into Never" do
    findings = analyze("u = User.new\nu.emial\n", index)[:findings]

    expect(findings.size).to eq(1)
    finding = findings.first
    expect(finding.name).to eq("u")
    expect(finding.node_type).to eq("LocalVariable")
    expect(finding.line).to eq(1)
    expect(finding.inferred_type).to eq("never")
    expect(finding.reason).to eq("User does not define emial")
  end

  it "reports zero-candidate duck-typed write sites" do
    findings = analyze("user = repo.find(1)\nuser.emial\n", index)[:findings]

    expect(findings.size).to eq(1)
    expect(findings.first.inferred_type).to eq("never")
  end

  it "counts Unknown sites as skipped instead of reporting them" do
    result = analyze("u = User.new\nu.email\nx = something\n", index)

    expect(result[:findings]).to be_empty
    expect(result[:skipped]).to eq(1)
  end

  it "works with a code index that cannot answer method existence" do
    result = analyze("u = User.new\nu.emial\n", InferenceHelper::StubIndexAdapter.new)

    expect(result[:findings]).to be_empty
  end
end
