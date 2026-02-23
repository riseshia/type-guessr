# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"
require "tmpdir"

RSpec.describe RubyLsp::TypeGuessr::Config do
  include TypeGuessrTestHelper

  around do |example|
    original_dir = Dir.pwd

    Dir.mktmpdir("type-guessr-enabled-") do |dir|
      Dir.chdir(dir) do
        described_class.reset!
        example.run
      ensure
        described_class.reset!
      end
    end
  ensure
    Dir.chdir(original_dir)
    # Restore the test-suite config so subsequent tests don't read .type-guessr.yml
    # (which lacks background_indexing, defaulting to true and spawning start_indexing threads)
    described_class.instance_variable_set(
      :@cached_config,
      { "enabled" => true, "debug" => false, "background_indexing" => false }
    )
  end

  before do
    # Allow real Config methods to be called (override spec_helper mock)
    allow(described_class).to receive(:debug?).and_call_original
    allow(described_class).to receive(:debug_server_enabled?).and_call_original
    allow(described_class).to receive(:debug_server_port).and_call_original
  end

  it "defaults enabled to true when config is missing" do
    expect(described_class.enabled?).to be(true)
  end

  describe ".debug_server_enabled?" do
    it "uses debug_server from config when set" do
      File.write(".type-guessr.yml", "debug_server: true\n")
      described_class.reset!
      expect(described_class.debug_server_enabled?).to be(true)
    end

    it "can disable debug_server independently from debug" do
      File.write(".type-guessr.yml", "debug: true\ndebug_server: false\n")
      described_class.reset!
      expect(described_class.debug?).to be(true)
      expect(described_class.debug_server_enabled?).to be(false)
    end

    it "defaults to debug? value when debug_server not specified" do
      File.write(".type-guessr.yml", "debug: true\n")
      described_class.reset!
      expect(described_class.debug_server_enabled?).to be(true)
    end
  end

  describe ".debug_server_port" do
    it "defaults to 7010 when not specified" do
      expect(described_class.debug_server_port).to eq(7010)
    end

    it "uses debug_server_port from config when set" do
      File.write(".type-guessr.yml", "debug_server_port: 8080\n")
      described_class.reset!
      expect(described_class.debug_server_port).to eq(8080)
    end
  end

  describe ".max_gem_files" do
    it "defaults to 500 when not specified" do
      expect(described_class.max_gem_files).to eq(500)
    end

    it "uses max_gem_files from config when set" do
      File.write(".type-guessr.yml", "max_gem_files: 1000\n")
      described_class.reset!
      expect(described_class.max_gem_files).to eq(1000)
    end
  end

  it "skips initialization in activate when enabled is false" do
    File.write(".type-guessr.yml", "enabled: false\n")
    described_class.reset!

    server = FullIndexHelper.server
    addon = RubyLsp::TypeGuessr::Addon.new
    addon.activate(server.global_state, server.instance_variable_get(:@outgoing_queue))

    expect(addon.runtime_adapter).to be_nil
  ensure
    addon&.deactivate
  end

  it "disables addon features when enabled is false" do
    File.write(".type-guessr.yml", "enabled: false\n")
    described_class.reset!

    source = <<~RUBY
      def foo
        name = "John"
        name
      end
    RUBY

    response = nil

    with_server_and_addon(source) do |server, uri|
      server.process_message(
        id: 1,
        method: "textDocument/hover",
        params: { textDocument: { uri: uri }, position: { line: 2, character: 2 } }
      )

      result = pop_result(server)
      response = result.response
    end

    # When disabled, the hover listener registers nothing, so Ruby LSP should return no hover result.
    expect(response).to be_nil
  end
end
