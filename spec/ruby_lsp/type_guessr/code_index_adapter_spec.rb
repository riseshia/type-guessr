# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

RSpec.describe RubyLsp::TypeGuessr::CodeIndexAdapter do
  include TypeGuessrTestHelper

  describe "#instance_method_owner" do
    it "returns Object for tap method on custom class" do
      source = <<~RUBY
        class MyClass
          def my_method
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # tap is defined in Object, so owner should be Object (or Kernel)
        owner = adapter.instance_method_owner("MyClass", "tap")
        expect(owner).to eq("Object").or eq("Kernel")
      end
    end

    it "returns the class itself for directly defined methods" do
      source = <<~RUBY
        class MyClass
          def my_method
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        owner = adapter.instance_method_owner("MyClass", "my_method")
        expect(owner).to eq("MyClass")
      end
    end

    it "returns nil when method not found" do
      source = <<~RUBY
        class MyClass
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        owner = adapter.instance_method_owner("MyClass", "nonexistent_method_xyz")
        expect(owner).to be_nil
      end
    end

    it "returns nil for nonexistent class" do
      source = <<~RUBY
        class MyClass
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        owner = adapter.instance_method_owner("NonexistentClass", "tap")
        expect(owner).to be_nil
      end
    end
  end
end
