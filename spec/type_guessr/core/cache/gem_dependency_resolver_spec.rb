# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "type_guessr/core/cache/gem_dependency_resolver"

RSpec.describe TypeGuessr::Core::Cache::GemDependencyResolver do
  def write_lockfile(dir, content)
    path = File.join(dir, "Gemfile.lock")
    File.write(path, content)
    path
  end

  let(:lockfile_content) do
    <<~LOCKFILE
      GEM
        remote: https://rubygems.org/
        specs:
          ast (2.4.2)
          parser (3.3.0)
            ast (~> 2.4.1)
          rubocop-ast (1.30.0)
            parser (>= 3.2.1)
          activesupport (7.1.0)
            concurrent-ruby (~> 1.0)
          concurrent-ruby (1.2.3)

      PLATFORMS
        ruby

      DEPENDENCIES
        parser
        rubocop-ast
        activesupport
    LOCKFILE
  end

  describe "#partition" do
    it "separates gem files from project files" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        file_paths = [
          "/home/user/.gem/ruby/3.3.0/gems/parser-3.3.0/lib/parser.rb",
          "/home/user/.gem/ruby/3.3.0/gems/ast-2.4.2/lib/ast.rb",
          "/home/user/project/app/models/user.rb",
          "/home/user/project/lib/helpers.rb",
        ]

        result = resolver.partition(file_paths)

        expect(result[:gems].keys).to contain_exactly("parser", "ast")
        expect(result[:gems]["parser"][:version]).to eq("3.3.0")
        expect(result[:gems]["parser"][:files]).to eq(["/home/user/.gem/ruby/3.3.0/gems/parser-3.3.0/lib/parser.rb"])
        expect(result[:gems]["ast"][:files]).to eq(["/home/user/.gem/ruby/3.3.0/gems/ast-2.4.2/lib/ast.rb"])
        expect(result[:project_files]).to contain_exactly(
          "/home/user/project/app/models/user.rb",
          "/home/user/project/lib/helpers.rb"
        )
      end
    end

    it "excludes gem files not in lockfile" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        file_paths = [
          "/home/user/.gem/ruby/3.3.0/gems/unknown-gem-1.0.0/lib/unknown.rb",
        ]

        result = resolver.partition(file_paths)

        expect(result[:gems]).to be_empty
        expect(result[:project_files]).to eq(["/home/user/.gem/ruby/3.3.0/gems/unknown-gem-1.0.0/lib/unknown.rb"])
      end
    end

    it "resolves transitive dependencies" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        file_paths = [
          "/home/user/.gem/ruby/3.3.0/gems/rubocop-ast-1.30.0/lib/rubocop_ast.rb",
        ]

        result = resolver.partition(file_paths)

        transitive = result[:gems]["rubocop-ast"][:transitive_deps]
        expect(transitive).to include("parser" => "3.3.0", "ast" => "2.4.2")
      end
    end

    it "groups multiple files from the same gem" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        file_paths = [
          "/home/user/.gem/ruby/3.3.0/gems/parser-3.3.0/lib/parser.rb",
          "/home/user/.gem/ruby/3.3.0/gems/parser-3.3.0/lib/parser/ast.rb",
        ]

        result = resolver.partition(file_paths)

        expect(result[:gems]["parser"][:files].size).to eq(2)
      end
    end

    it "handles empty file_paths" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        result = resolver.partition([])

        expect(result[:gems]).to be_empty
        expect(result[:project_files]).to be_empty
      end
    end
  end

  describe "#topological_order" do
    it "returns dependencies before dependents" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        order = resolver.topological_order(%w[rubocop-ast parser ast])

        expect(order.index("ast")).to be < order.index("parser")
        expect(order.index("parser")).to be < order.index("rubocop-ast")
      end
    end

    it "handles gems with no dependencies" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        order = resolver.topological_order(%w[ast concurrent-ruby])

        expect(order).to contain_exactly("ast", "concurrent-ruby")
      end
    end

    it "only includes valid_names in result" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        # rubocop-ast depends on parser, but parser is not in valid_names
        order = resolver.topological_order(%w[rubocop-ast])

        expect(order).to eq(%w[rubocop-ast])
      end
    end

    it "handles empty input" do
      Dir.mktmpdir do |dir|
        lockfile_path = write_lockfile(dir, lockfile_content)
        resolver = described_class.new(lockfile_path)

        order = resolver.topological_order([])

        expect(order).to eq([])
      end
    end
  end

  describe "with missing lockfile" do
    it "returns empty gems and all files as project files" do
      resolver = described_class.new("/nonexistent/Gemfile.lock")

      file_paths = [
        "/home/user/.gem/ruby/3.3.0/gems/parser-3.3.0/lib/parser.rb",
        "/home/user/project/lib/app.rb",
      ]

      result = resolver.partition(file_paths)

      expect(result[:gems]).to be_empty
      expect(result[:project_files]).to eq(file_paths)
    end

    it "returns empty topological order" do
      resolver = described_class.new("/nonexistent/Gemfile.lock")

      order = resolver.topological_order(%w[parser])

      expect(order).to eq(%w[parser])
    end
  end
end
