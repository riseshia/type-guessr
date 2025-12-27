# frozen_string_literal: true

require "spec_helper"
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
    described_class.reset!
  end

  it "defaults enabled to true when config is missing" do
    expect(described_class.enabled?).to be(true)
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
