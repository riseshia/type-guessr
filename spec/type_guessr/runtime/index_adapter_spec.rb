# frozen_string_literal: true

require "spec_helper"
require "type_guessr/runtime/index_adapter"

RSpec.describe TypeGuessr::Runtime::IndexAdapter do
  # Records every IPC round trip so the spec can count them.
  let(:client) do
    Class.new do
      attr_reader :calls

      def initialize
        @calls = []
      end

      def method_defined?(class_name, method_name, **opts)
        @calls << [:method_defined?, class_name, method_name, opts]
        method_name == "email"
      end

      def constant_kind(name)
        @calls << [:constant_kind, name]
        "class"
      end
    end.new
  end
  let(:adapter) { described_class.new(client) }

  describe "#method_defined?" do
    it "asks the server once per distinct call signature" do
      3.times { adapter.method_defined?("User", "email", singleton: false, positional_count: 0, keywords: []) }
      adapter.method_defined?("User", "email", singleton: true, positional_count: 0, keywords: [])

      expect(client.calls.count { |c| c.first == :method_defined? }).to eq(2)
    end

    it "caches a negative answer too" do
      expect(adapter.method_defined?("User", "emial")).to be(false)
      expect(adapter.method_defined?("User", "emial")).to be(false)

      expect(client.calls.count { |c| c.first == :method_defined? }).to eq(1)
    end
  end

  describe "#constant_kind" do
    it "asks the server once per constant" do
      2.times { expect(adapter.constant_kind("User")).to eq(:class) }

      expect(client.calls.count { |c| c.first == :constant_kind }).to eq(1)
    end
  end
end
