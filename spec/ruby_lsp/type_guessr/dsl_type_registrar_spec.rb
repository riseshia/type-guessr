# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "type_guessr/core/registry/signature_registry"
require "ruby_lsp/type_guessr/dsl_type_registrar"

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe RubyLsp::TypeGuessr::DslTypeRegistrar do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }
  let(:cache_dir) { File.join(tmpdir, "cache") }
  let(:signature_registry) { TypeGuessr::Core::Registry::SignatureRegistry.new }
  let(:code_index) { instance_double(RubyLsp::TypeGuessr::CodeIndexAdapter) }
  let(:adapter) do
    RubyLsp::TypeGuessr::Dsl::ActiveRecordAdapter.new(
      project_root: project_root,
      cache_dir: cache_dir
    )
  end
  let(:registrar) do
    described_class.new(
      signature_registry: signature_registry,
      code_index: code_index,
      project_root: project_root,
      adapters: [adapter]
    )
  end

  before do
    FileUtils.mkdir_p(File.join(project_root, "app", "models"))
    FileUtils.mkdir_p(File.join(project_root, "db"))
    allow(code_index).to receive(:register_method_class)
    allow(code_index).to receive(:unregister_method_classes)
  end

  after { FileUtils.rm_rf(tmpdir) }

  def metadata_response(columns: [], enums: {}, associations: [], scopes: [])
    { columns: columns, enums: enums, associations: associations, scopes: scopes }
  end

  def stub_runner_client(runner_client, model_responses)
    allow(runner_client).to receive(:connected?).and_return(true)
    allow(runner_client).to receive(:register_server_addon)
    model_responses.each do |class_name, response|
      allow(runner_client).to receive(:delegate_request).with(
        server_addon_name: "TypeGuessr",
        request_name: "model_metadata",
        name: class_name
      ).and_return(response)
    end
  end

  describe "#register_all" do
    it "registers base methods and model data" do
      File.write(File.join(project_root, "app", "models", "user.rb"), "class User; end")
      File.write(File.join(project_root, "db", "schema.rb"), "schema content")

      runner_client = double("RunnerClient")
      stub_runner_client(runner_client, "User" => metadata_response(
        columns: [["name", "string", true]]
      ))

      registrar.register_all(runner_client: runner_client)

      # Base methods registered
      where_type = signature_registry.get_class_method_return_type("ActiveRecord::Base", "where")
      expect(where_type.to_s).to include("ActiveRecord::Relation")

      # Model methods registered
      expect(signature_registry.get_method_return_type("User", "name").to_s).to eq("?String")
    end

    it "registers base methods only once" do
      registrar.register_all
      registrar.register_all

      where_type = signature_registry.get_class_method_return_type("ActiveRecord::Base", "where")
      expect(where_type.to_s).to include("ActiveRecord::Relation")
    end
  end

  describe "#check_and_refresh" do
    it "refreshes when adapter reports change" do
      File.write(File.join(project_root, "app", "models", "user.rb"), "class User; end")
      File.write(File.join(project_root, "db", "schema.rb"), "schema1")

      runner_client = double("RunnerClient")
      stub_runner_client(runner_client, "User" => metadata_response(
        columns: [["name", "string", true]]
      ))

      registrar.register_all(runner_client: runner_client)

      # Simulate schema change
      File.write(File.join(project_root, "db", "schema.rb"), "schema2")

      stub_runner_client(runner_client, "User" => metadata_response(
        columns: [["email", "string", true]]
      ))

      registrar.check_and_refresh(runner_client: runner_client)

      expect(code_index).to have_received(:unregister_method_classes).with("User")
      expect(signature_registry.get_method_return_type("User", "email").to_s).to eq("?String")
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
