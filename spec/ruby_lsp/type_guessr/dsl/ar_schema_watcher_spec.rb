# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "ruby_lsp/type_guessr/dsl/ar_schema_watcher"

RSpec.describe RubyLsp::TypeGuessr::Dsl::ArSchemaWatcher do
  let(:tmpdir) { Dir.mktmpdir }
  let(:cache_dir) { File.join(tmpdir, "cache") }
  let(:project_root) { File.join(tmpdir, "project") }
  let(:watcher) { described_class.new(project_root, cache_dir: cache_dir) }

  before do
    FileUtils.mkdir_p(File.join(project_root, "db"))
  end

  after { FileUtils.rm_rf(tmpdir) }

  describe "#schema_files" do
    it "finds schema.rb in db/" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      expect(watcher.schema_files).to eq([File.join(project_root, "db", "schema.rb")])
    end

    it "finds structure.sql in db/" do
      File.write(File.join(project_root, "db", "structure.sql"), "content")
      expect(watcher.schema_files).to eq([File.join(project_root, "db", "structure.sql")])
    end

    it "returns empty array when no schema files exist" do
      expect(watcher.schema_files).to eq([])
    end
  end

  describe "#current_hash" do
    it "returns 'empty' when no schema files exist" do
      expect(watcher.current_hash).to eq("empty")
    end

    it "returns consistent hash for same content" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      hash1 = watcher.current_hash
      hash2 = watcher.current_hash
      expect(hash1).to eq(hash2)
    end

    it "returns different hash for different content" do
      schema_path = File.join(project_root, "db", "schema.rb")
      File.write(schema_path, "content1")
      hash1 = watcher.current_hash
      File.write(schema_path, "content2")
      expect(watcher.current_hash).not_to eq(hash1)
    end
  end

  describe "#changed?" do
    it "returns true on first call" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      expect(watcher.changed?).to be(true)
    end

    it "returns false on second call without changes" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      watcher.changed?
      expect(watcher.changed?).to be(false)
    end

    it "returns true after schema content changes" do
      schema_path = File.join(project_root, "db", "schema.rb")
      File.write(schema_path, "content1")
      watcher.changed?
      File.write(schema_path, "content2")
      expect(watcher.changed?).to be(true)
    end
  end

  describe "#load_cache / #save_cache" do
    it "returns nil when no cache exists" do
      expect(watcher.load_cache).to be_nil
    end

    it "round-trips cached data" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      data = { "User" => { "name" => { "type" => "string", "nullable" => true } } }
      watcher.save_cache(data)
      expect(watcher.load_cache).to eq(data)
    end

    it "returns nil when schema has changed since cache was saved" do
      schema_path = File.join(project_root, "db", "schema.rb")
      File.write(schema_path, "content1")
      watcher.save_cache({ "User" => {} })
      File.write(schema_path, "content2")
      expect(watcher.load_cache).to be_nil
    end
  end

  describe "#clear_cache" do
    it "removes the cache file" do
      File.write(File.join(project_root, "db", "schema.rb"), "content")
      watcher.save_cache({ "User" => {} })
      watcher.clear_cache
      expect(watcher.load_cache).to be_nil
    end
  end
end
