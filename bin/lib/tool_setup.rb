# frozen_string_literal: true

# Shared setup for CLI tools (benchmark, coverage, profile).
# Provides production-like infrastructure with real code_index
# instead of nil, matching the RuntimeAdapter initialization flow.

require "English"
require "uri/generic"
require_relative "../../lib/ruby_lsp/type_guessr/code_index_adapter"

# Shared infrastructure setup for CLI tools (benchmark, coverage, profile)
module ToolSetup
  Infrastructure = Data.define(
    :code_index, :signature_registry, :method_registry,
    :ivar_registry, :cvar_registry, :type_simplifier, :resolver
  )

  # Build RubyIndexer::Index and wrap it in CodeIndexAdapter.
  # Expensive operation — call once per session.
  # @param files [Array<String>] Absolute file paths to index
  # @return [RubyLsp::TypeGuessr::CodeIndexAdapter]
  def self.build_code_index(files)
    ruby_index = RubyIndexer::Index.new
    files.each do |file_path|
      uri = URI::Generic.build(path: file_path)
      source = File.read(file_path)
      ruby_index.index_single(uri, source)
    rescue StandardError
      # Skip files that fail to index
    end

    code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(ruby_index)
    code_index.build_member_index!
    code_index
  end

  # Build fresh registries and resolver from a code_index.
  # Cheap enough to call multiple times (e.g., per benchmark run).
  # @param code_index [RubyLsp::TypeGuessr::CodeIndexAdapter]
  # @return [Infrastructure]
  def self.build_infrastructure(code_index)
    signature_registry = TypeGuessr::Core::Registry::SignatureRegistry.instance.preload
    method_registry = TypeGuessr::Core::Registry::MethodRegistry.new(code_index: code_index)
    ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
    cvar_registry = TypeGuessr::Core::Registry::ClassVariableRegistry.new
    type_simplifier = TypeGuessr::Core::TypeSimplifier.new(code_index: code_index)

    resolver = TypeGuessr::Core::Inference::Resolver.new(
      signature_registry,
      code_index: code_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry,
      type_simplifier: type_simplifier
    )

    Infrastructure.new(
      code_index: code_index,
      signature_registry: signature_registry,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry,
      type_simplifier: type_simplifier,
      resolver: resolver
    )
  end

  # Build PrismConverter::Context with all registries injected.
  # @param infra [Infrastructure]
  # @param file_path [String]
  # @param location_index [TypeGuessr::Core::Index::LocationIndex]
  # @return [TypeGuessr::Core::Converter::PrismConverter::Context]
  def self.build_context(infra, file_path:, location_index:)
    TypeGuessr::Core::Converter::PrismConverter::Context.new(
      file_path: file_path,
      location_index: location_index,
      method_registry: infra.method_registry,
      ivar_registry: infra.ivar_registry,
      cvar_registry: infra.cvar_registry
    )
  end

  # Collect indexable file paths for a project.
  # @param path [String, nil] Project directory (nil = current directory)
  # @return [Array<String>] Absolute file paths
  def self.collect_indexable_files(path: nil)
    if path
      collect_files_from_project(path)
    else
      config = RubyIndexer::Configuration.new
      config.indexable_uris.map { |uri| uri.full_path.to_s }
    end
  end

  # Collect files from a different project using subprocess.
  # Runs in the target project's Bundler environment.
  def self.collect_files_from_project(project_path)
    script = <<~RUBY
      require 'bundler/setup'
      require 'ruby_indexer/ruby_indexer'
      config = RubyIndexer::Configuration.new
      config.indexable_uris.each { |uri| puts uri.full_path }
    RUBY

    clean_env = ENV.to_h.reject { |k, _| k.start_with?("BUNDLE_", "RUBYGEMS_", "GEM_") }
    clean_env["BUNDLE_GEMFILE"] = File.join(project_path, "Gemfile")

    output = IO.popen(clean_env, ["ruby"], "r+", chdir: project_path, err: %i[child out]) do |io|
      io.write(script)
      io.close_write
      io.read
    end

    unless $CHILD_STATUS.success?
      warn "Warning: Failed to collect files from #{project_path}"
      warn "Falling back to current directory scan"
      Dir.chdir(project_path) do
        config = RubyIndexer::Configuration.new
        return config.indexable_uris.map { |uri| uri.full_path.to_s }
      end
    end

    output.lines.map(&:chomp)
  end
  private_class_method :collect_files_from_project
end
