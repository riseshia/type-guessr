# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

# Tests for gem method parameter names lookup.
# These tests verify that the full indexing includes gems/stdlib.
#
# Related issue from todo.md:
# - Problem: gem class method calls show "arg1" instead of actual parameter names
# - Expected: `(untyped loader) -> untyped`
# - Actual: `(RBS::EnvironmentLoader arg1) -> untyped`
# - Cause: lookup_class_method_entry doesn't find gem method entries in RubyIndexer
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Gem Method Integration" do
  include TypeGuessrTestHelper

  describe "RubyIndexer contains gem method entries" do
    it "can find RBS::EnvironmentLoader in the index" do
      with_server_and_addon("") do |server, _uri|
        # Verify RBS::EnvironmentLoader is indexed
        entries = server.global_state.index["RBS::EnvironmentLoader"]
        expect(entries).not_to be_nil, "RBS::EnvironmentLoader should be in the index"
        expect(entries).not_to be_empty, "RBS::EnvironmentLoader should have entries"
      end
    end

    it "has File class indexed" do
      with_server_and_addon("") do |server, _uri|
        entries = server.global_state.index["File"]
        expect(entries).not_to be_nil, "File should be in the index"
        expect(entries).not_to be_empty, "File should have entries"
      end
    end
  end

  describe "Gem class method resolution" do
    it "can resolve File.read method from stdlib" do
      with_server_and_addon("") do |server, _uri|
        # File.read is a class method, but in RubyIndexer it's stored differently
        # The singleton class is accessed via "<Class:File>"
        methods = server.global_state.index.resolve_method("read", "File")
        expect(methods).not_to be_nil, "Should be able to resolve File.read method"
      end
    end

    it "can access method parameters from resolved methods" do
      with_server_and_addon("") do |server, _uri|
        methods = server.global_state.index.resolve_method("read", "File")
        next skip "File.read not resolvable in current index" if methods.nil?

        # Check that we can access parameter information
        method_entry = methods.first
        expect(method_entry).to respond_to(:signatures)
      end
    end
  end

  describe "Full indexing verification" do
    it "index has many entries from stdlib and gems" do
      with_server_and_addon("") do |server, _uri|
        full_index_entry_count = server.global_state.index.instance_variable_get(:@entries).size
        # Full index should have significantly more entries (stdlib + gems)
        expect(full_index_entry_count).to be > 1000,
                                          "Full index should have many entries. Got: #{full_index_entry_count}"
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
