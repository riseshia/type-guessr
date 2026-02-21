# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "type_guessr/core/cache/gem_signature_cache"

RSpec.describe TypeGuessr::Core::Cache::GemSignatureCache do
  let(:gem_name) { "activesupport" }
  let(:gem_version) { "7.1.0" }
  let(:transitive_deps) { { "i18n" => "1.14.0", "tzinfo" => "2.0.6" } }
  let(:instance_methods) do
    {
      "ActiveSupport::Duration" => {
        "to_i" => { "_type" => "ClassInstance", "name" => "Integer" }
      }
    }
  end
  let(:class_methods) do
    {
      "ActiveSupport::Duration" => {
        "build" => { "_type" => "ClassInstance", "name" => "ActiveSupport::Duration" }
      }
    }
  end

  describe "#cached?" do
    it "returns false when no cache exists" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)

        expect(cache.cached?(gem_name, gem_version, transitive_deps)).to be false
      end
    end

    it "returns true after saving" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)
        cache.save(gem_name, gem_version, transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)

        expect(cache.cached?(gem_name, gem_version, transitive_deps)).to be true
      end
    end
  end

  describe "#save and #load" do
    it "round-trips instance_methods and class_methods" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)
        cache.save(gem_name, gem_version, transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)

        result = cache.load(gem_name, gem_version, transitive_deps)

        expect(result).to eq({
                               "instance_methods" => instance_methods,
                               "class_methods" => class_methods
                             })
      end
    end

    it "produces different cache files for different versions" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)
        cache.save(gem_name, "7.1.0", transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)
        cache.save(gem_name, "7.2.0", transitive_deps,
                   instance_methods: {}, class_methods: {})

        result_v1 = cache.load(gem_name, "7.1.0", transitive_deps)
        result_v2 = cache.load(gem_name, "7.2.0", transitive_deps)

        expect(result_v1["instance_methods"]).to eq(instance_methods)
        expect(result_v2["instance_methods"]).to eq({})
      end
    end

    it "produces different cache files for different transitive_deps" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)
        deps_a = { "i18n" => "1.14.0" }
        deps_b = { "i18n" => "1.15.0" }

        cache.save(gem_name, gem_version, deps_a,
                   instance_methods: instance_methods, class_methods: class_methods)
        cache.save(gem_name, gem_version, deps_b,
                   instance_methods: {}, class_methods: {})

        result_a = cache.load(gem_name, gem_version, deps_a)
        result_b = cache.load(gem_name, gem_version, deps_b)

        expect(result_a["instance_methods"]).to eq(instance_methods)
        expect(result_b["instance_methods"]).to eq({})
      end
    end

    it "works correctly with empty transitive_deps" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)
        cache.save(gem_name, gem_version, {},
                   instance_methods: instance_methods, class_methods: class_methods)

        result = cache.load(gem_name, gem_version, {})

        expect(result).to eq({
                               "instance_methods" => instance_methods,
                               "class_methods" => class_methods
                             })
      end
    end
  end

  describe "#load" do
    it "returns nil for corrupt JSON" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)

        # Save valid data first to get the correct path, then corrupt it
        cache.save(gem_name, gem_version, transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)

        # Find and corrupt the cache file
        json_files = Dir.glob(File.join(dir, "*.json"))
        File.write(json_files.first, "not valid json{{{")

        result = cache.load(gem_name, gem_version, transitive_deps)

        expect(result).to be_nil
      end
    end

    it "returns nil for wrong format version" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)

        # Save valid data first to get the correct path, then overwrite with wrong version
        cache.save(gem_name, gem_version, transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)

        json_files = Dir.glob(File.join(dir, "*.json"))
        wrong_version_data = {
          "version" => 999,
          "instance_methods" => instance_methods,
          "class_methods" => class_methods
        }
        File.write(json_files.first, JSON.generate(wrong_version_data))

        result = cache.load(gem_name, gem_version, transitive_deps)

        expect(result).to be_nil
      end
    end

    it "returns nil when cache file does not exist" do
      Dir.mktmpdir do |dir|
        cache = described_class.new(cache_dir: dir)

        result = cache.load(gem_name, gem_version, transitive_deps)

        expect(result).to be_nil
      end
    end
  end

  describe "#clear!" do
    it "removes all cached files" do
      dir = Dir.mktmpdir
      begin
        cache = described_class.new(cache_dir: dir)
        cache.save(gem_name, gem_version, transitive_deps,
                   instance_methods: instance_methods, class_methods: class_methods)
        cache.save("nokogiri", "1.16.0", {},
                   instance_methods: {}, class_methods: {})

        cache.clear!

        expect(Dir.exist?(dir)).to be false
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
