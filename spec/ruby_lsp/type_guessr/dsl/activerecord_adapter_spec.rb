# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "type_guessr/core/registry/signature_registry"
require "ruby_lsp/type_guessr/dsl/activerecord_adapter"

# rubocop:disable RSpec/VerifiedDoubles
RSpec.describe RubyLsp::TypeGuessr::Dsl::ActiveRecordAdapter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }
  let(:cache_dir) { File.join(tmpdir, "cache") }
  let(:signature_registry) { TypeGuessr::Core::Registry::SignatureRegistry.new }
  let(:code_index) { instance_double(RubyLsp::TypeGuessr::CodeIndexAdapter) }
  let(:adapter) do
    described_class.new(project_root: project_root, cache_dir: cache_dir)
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

  describe "#applicable?" do
    it "returns true when app/models exists" do
      expect(adapter.applicable?).to be(true)
    end

    it "returns false when app/models does not exist" do
      FileUtils.rm_rf(File.join(project_root, "app", "models"))
      expect(adapter.applicable?).to be(false)
    end
  end

  describe "#register_base_methods" do
    it "registers AR::Base class methods with SelfType" do
      adapter.register_base_methods(signature_registry: signature_registry)

      where_type = signature_registry.get_class_method_return_type("ActiveRecord::Base", "where")
      expect(where_type.to_s).to include("ActiveRecord::Relation")

      first_type = signature_registry.get_class_method_return_type("ActiveRecord::Base", "first")
      expect(first_type.to_s).not_to eq("unknown")
    end
  end

  describe "#register_models" do
    context "with RunnerClient" do
      let(:runner_client) { double("RunnerClient") }

      before do
        File.write(File.join(project_root, "app", "models", "user.rb"), "class User; end")
        File.write(File.join(project_root, "db", "schema.rb"), "schema content")
      end

      it "registers column accessors" do
        stub_runner_client(runner_client, "User" => metadata_response(
          columns: [["name", "string", true], ["age", "integer", true]]
        ))

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        expect(signature_registry.get_method_return_type("User", "name").to_s).to eq("?String")
        expect(signature_registry.get_method_return_type("User", "age").to_s).to eq("?Integer")
      end

      it "registers enum methods" do
        stub_runner_client(runner_client, "User" => metadata_response(
          columns: [["role", "integer", true]],
          enums: { "role" => { "member" => 0, "admin" => 1 } }
        ))

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        role_type = signature_registry.get_method_return_type("User", "role")
        expect(role_type.to_s).to eq("?String")

        admin_type = signature_registry.get_method_return_type("User", "admin?")
        expect(admin_type.to_s).to eq("bool")
      end

      it "registers association methods" do
        stub_runner_client(runner_client, "User" => metadata_response(
          associations: [
            { name: "posts", macro: "has_many", class_name: "Post" },
            { name: "profile", macro: "has_one", class_name: "Profile" },
          ]
        ))

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        posts_type = signature_registry.get_method_return_type("User", "posts")
        expect(posts_type.to_s).to eq("ActiveRecord::Associations::CollectionProxy[Post]")

        profile_type = signature_registry.get_method_return_type("User", "profile")
        expect(profile_type.to_s).to eq("?Profile")
      end

      it "registers scope as class method" do
        stub_runner_client(runner_client, "User" => metadata_response(
          scopes: %w[active adults]
        ))

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        active_type = signature_registry.get_class_method_return_type("User", "active")
        expect(active_type.to_s).to eq("ActiveRecord::Relation[User]")
      end

      it "registers method_classes for duck typing" do
        stub_runner_client(runner_client, "User" => metadata_response(
          columns: [["name", "string", true]]
        ))

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        expect(code_index).to have_received(:register_method_class).with("User", "name")
      end

      it "skips models that return nil" do
        stub_runner_client(runner_client, "User" => nil)

        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        expect(signature_registry.get_method_return_type("User", "name"))
          .to be_a(TypeGuessr::Core::Types::Unknown)
      end
    end

    context "without RunnerClient" do
      it "does nothing when no cache exists" do
        adapter.register_models(
          runner_client: nil,
          signature_registry: signature_registry,
          code_index: code_index
        )

        expect(signature_registry.get_method_return_type("User", "name"))
          .to be_a(TypeGuessr::Core::Types::Unknown)
      end
    end

    context "with cache" do
      it "loads from cache without RunnerClient" do
        File.write(File.join(project_root, "app", "models", "user.rb"), "class User; end")
        File.write(File.join(project_root, "db", "schema.rb"), "schema")

        runner_client = double("RunnerClient")
        stub_runner_client(runner_client, "User" => metadata_response(
          columns: [["email", "string", true]]
        ))
        adapter.register_models(
          runner_client: runner_client,
          signature_registry: signature_registry,
          code_index: code_index
        )

        # New adapter — should load from cache
        adapter2 = described_class.new(project_root: project_root, cache_dir: cache_dir)
        adapter2.register_models(
          runner_client: nil,
          signature_registry: signature_registry,
          code_index: code_index
        )

        expect(signature_registry.get_method_return_type("User", "email").to_s).to eq("?String")
      end
    end
  end

  describe "#changed?" do
    it "delegates to ArSchemaWatcher" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      expect(adapter.changed?).to be(true)
      expect(adapter.changed?).to be(false)
    end
  end

  describe "#refresh" do
    it "purges old data and re-registers" do
      File.write(File.join(project_root, "app", "models", "user.rb"), "class User; end")
      File.write(File.join(project_root, "db", "schema.rb"), "schema")

      runner_client = double("RunnerClient")
      stub_runner_client(runner_client, "User" => metadata_response(
        columns: [["name", "string", true]]
      ))

      adapter.register_models(
        runner_client: runner_client,
        signature_registry: signature_registry,
        code_index: code_index
      )

      # Refresh with new data
      stub_runner_client(runner_client, "User" => metadata_response(
        columns: [["email", "string", true]]
      ))

      adapter.refresh(
        runner_client: runner_client,
        signature_registry: signature_registry,
        code_index: code_index
      )

      expect(code_index).to have_received(:unregister_method_classes).with("User")
      expect(signature_registry.get_method_return_type("User", "email").to_s).to eq("?String")
    end
  end

  describe "discover_models (via register_models)" do
    it "skips application_record and concerns" do
      File.write(File.join(project_root, "app", "models", "application_record.rb"), "")
      FileUtils.mkdir_p(File.join(project_root, "app", "models", "concerns"))
      File.write(File.join(project_root, "app", "models", "concerns", "searchable.rb"), "")
      File.write(File.join(project_root, "app", "models", "post.rb"), "class Post; end")
      File.write(File.join(project_root, "db", "schema.rb"), "schema")

      runner_client = double("RunnerClient")
      stub_runner_client(runner_client, "Post" => metadata_response(
        columns: [["title", "string", true]]
      ))

      adapter.register_models(
        runner_client: runner_client,
        signature_registry: signature_registry,
        code_index: code_index
      )

      expect(runner_client).to have_received(:delegate_request).with(
        server_addon_name: "TypeGuessr",
        request_name: "model_metadata",
        name: "Post"
      )
    end
  end
end
# rubocop:enable RSpec/VerifiedDoubles
