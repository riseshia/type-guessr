# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

RSpec.describe RubyLsp::TypeGuessr::CodeIndexAdapter do
  include TypeGuessrTestHelper

  describe "#resolve_constant_name" do
    it "resolves short constant name within same module nesting" do
      source = <<~RUBY
        module Outer
          class Inner
          end

          class User
            def create
              Inner.new
            end
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # When nesting is ["Outer"], "Inner" should resolve to "Outer::Inner"
        result = adapter.resolve_constant_name("Inner", ["Outer"])
        expect(result).to eq("Outer::Inner")
      end
    end

    it "resolves constant with deeper nesting" do
      source = <<~RUBY
        module A
          module B
            class Target
            end

            class User
              def method
                Target.new
              end
            end
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # When nesting is ["A", "B"], "Target" should resolve to "A::B::Target"
        result = adapter.resolve_constant_name("Target", %w[A B])
        expect(result).to eq("A::B::Target")
      end
    end

    it "returns nil for non-existent constant" do
      source = <<~RUBY
        module Outer
          class Inner
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        result = adapter.resolve_constant_name("NonExistent", ["Outer"])
        expect(result).to be_nil
      end
    end

    it "resolves top-level constant from any nesting" do
      source = <<~RUBY
        class TopLevel
        end

        module Outer
          class Inner
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # TopLevel is at top-level, should be found even from ["Outer"] nesting
        result = adapter.resolve_constant_name("TopLevel", ["Outer"])
        expect(result).to eq("TopLevel")
      end
    end

    it "returns nil when index is nil" do
      adapter = described_class.new(nil)

      result = adapter.resolve_constant_name("Something", ["Outer"])
      expect(result).to be_nil
    end
  end

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
