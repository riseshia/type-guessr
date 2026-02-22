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

  describe "#find_classes_defining_methods" do
    # Helper to create CalledMethod with defaults
    def cm(name, positional_count: nil, keywords: [])
      TypeGuessr::Core::IR::CalledMethod.new(name: name, positional_count: positional_count, keywords: keywords)
    end

    it "finds classes defining methods via def" do
      source = <<~RUBY
        class Recipe
          def comments
          end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        result = adapter.find_classes_defining_methods([cm(:comments)])
        expect(result).to include("Recipe")
      end
    end

    it "finds classes defining methods via attr_reader" do
      source = <<~RUBY
        class DefNode
          attr_reader :name, :params
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        result = adapter.find_classes_defining_methods([cm(:name), cm(:params)])
        expect(result).to include("DefNode")
      end
    end

    it "returns intersection of classes defining all methods" do
      source = <<~RUBY
        class A
          def foo; end
          def bar; end
        end

        class B
          def foo; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        result = adapter.find_classes_defining_methods([cm(:foo), cm(:bar)])
        expect(result).to include("A")
        expect(result).not_to include("B")
      end
    end

    it "returns empty array for empty called_methods" do
      adapter = described_class.new(nil)

      result = adapter.find_classes_defining_methods([])
      expect(result).to eq([])
    end

    it "filters by positional_count to narrow candidates" do
      source = <<~RUBY
        class Narrow
          def process(a, b); end
        end

        class Wide
          def process(a); end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # process(a, b) → positional_count=2 should match Narrow but not Wide
        result = adapter.find_classes_defining_methods([cm(:process, positional_count: 2)])
        expect(result).to include("Narrow")
        expect(result).not_to include("Wide")
      end
    end

    it "skips positional_count filtering when nil (splat usage)" do
      source = <<~RUBY
        class Narrow
          def process(a, b); end
        end

        class Wide
          def process(a); end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # nil positional_count → match by name only
        result = adapter.find_classes_defining_methods([cm(:process, positional_count: nil)])
        expect(result).to include("Narrow")
        expect(result).to include("Wide")
      end
    end

    it "matches rest parameter accepting extra arguments" do
      source = <<~RUBY
        class Flexible
          def process(a, *rest); end
        end

        class Strict
          def process(a); end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # process(a, b, c) → positional_count=3 should match Flexible but not Strict
        result = adapter.find_classes_defining_methods([cm(:process, positional_count: 3)])
        expect(result).to include("Flexible")
        expect(result).not_to include("Strict")
      end
    end

    it "finds subclass when method is inherited from parent" do
      source = <<~RUBY
        class Parent
          def location; end
        end

        class Child < Parent
          def arguments; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        result = adapter.find_classes_defining_methods([cm(:arguments), cm(:location)])
        expect(result).to include("Child")
        expect(result).not_to include("Parent")
      end
    end

    it "matches attr_reader with positional_count 0" do
      source = <<~RUBY
        class Node
          attr_reader :name
        end

        class Other
          def name(arg); end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)

        # obj.name → positional_count=0 should match attr_reader (Node) but not Other
        result = adapter.find_classes_defining_methods([cm(:name, positional_count: 0)])
        expect(result).to include("Node")
        expect(result).not_to include("Other")
      end
    end
  end

  describe "#build_member_index! and member_index lookup" do
    # Helper to create CalledMethod with defaults
    def cm(name, positional_count: nil, keywords: [])
      TypeGuessr::Core::IR::CalledMethod.new(name: name, positional_count: positional_count, keywords: keywords)
    end

    it "uses member_index for find_classes_defining_methods after build" do
      source = <<~RUBY
        class Recipe
          def comments; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        result = adapter.find_classes_defining_methods([cm(:comments)])
        expect(result).to include("Recipe")
      end
    end

    it "all existing find_classes_defining_methods tests pass with member_index" do
      source = <<~RUBY
        class A
          def foo; end
          def bar; end
        end

        class B
          def foo; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        result = adapter.find_classes_defining_methods([cm(:foo), cm(:bar)])
        expect(result).to include("A")
        expect(result).not_to include("B")
      end
    end

    it "finds subclass when inherited method is pivot after build" do
      source = <<~RUBY
        class Parent
          def very_long_method_name; end
        end

        class Child < Parent
          def short; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        # "very_long_method_name" (21 chars) is pivot over "short" (5 chars)
        # Pivot is inherited (defined in Parent), so Child must appear in candidates
        result = adapter.find_classes_defining_methods([cm(:very_long_method_name), cm(:short)])
        expect(result).to include("Child")
        expect(result).not_to include("Parent")
      end
    end

    it "falls back to fuzzy_search when member_index not built" do
      source = <<~RUBY
        class Recipe
          def comments; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        # Do NOT call build_member_index!

        result = adapter.find_classes_defining_methods([cm(:comments)])
        expect(result).to include("Recipe")
      end
    end
  end

  describe "#refresh_member_index!" do
    # Helper to create CalledMethod with defaults
    def cm(name, positional_count: nil, keywords: [])
      TypeGuessr::Core::IR::CalledMethod.new(name: name, positional_count: positional_count, keywords: keywords)
    end

    it "reflects added methods after file re-index" do
      source = <<~RUBY
        class Recipe
          def comments; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        # Verify initial state
        result = adapter.find_classes_defining_methods([cm(:comments)])
        expect(result).to include("Recipe")

        # Add a new class with a new method
        updated_source = <<~RUBY
          class Recipe
            def comments; end
          end

          class Blog
            def posts; end
          end
        RUBY

        uri = URI("file://#{Dir.pwd}/source.rb")
        server.global_state.index.handle_change(uri, updated_source)
        adapter.refresh_member_index!(uri)

        result = adapter.find_classes_defining_methods([cm(:posts)])
        expect(result).to include("Blog")
      end
    end

    it "reflects removed methods after file re-index" do
      source = <<~RUBY
        class Recipe
          def comments; end
        end

        class Blog
          def posts; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        # Verify both exist
        expect(adapter.find_classes_defining_methods([cm(:posts)])).to include("Blog")

        # Remove Blog from source
        updated_source = <<~RUBY
          class Recipe
            def comments; end
          end
        RUBY

        uri = URI("file://#{Dir.pwd}/source.rb")
        server.global_state.index.handle_change(uri, updated_source)
        adapter.refresh_member_index!(uri)

        result = adapter.find_classes_defining_methods([cm(:posts)])
        expect(result).not_to include("Blog")
      end
    end

    it "skips when member_index not built" do
      adapter = described_class.new(nil)
      # Should not raise
      expect { adapter.refresh_member_index!(URI("file:///fake.rb")) }.not_to raise_error
    end
  end

  describe "#member_entries_for_file" do
    it "returns member entries for a file after build_member_index!" do
      source = <<~RUBY
        class Recipe
          def comments; end
          def title; end
        end
      RUBY

      with_server_and_addon(source) do |server, uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        file_path = uri.to_standardized_path
        entries = adapter.member_entries_for_file(file_path)

        method_names = entries.map(&:name)
        expect(method_names).to include("comments")
        expect(method_names).to include("title")
      end
    end

    it "returns empty array when member_index not built" do
      adapter = described_class.new(nil)

      result = adapter.member_entries_for_file("/some/path.rb")
      expect(result).to eq([])
    end

    it "returns empty array for file with no members" do
      source = <<~RUBY
        class Recipe
          def comments; end
        end
      RUBY

      with_server_and_addon(source) do |server, _uri|
        adapter = described_class.new(server.global_state.index)
        adapter.build_member_index!

        result = adapter.member_entries_for_file("/nonexistent/path.rb")
        expect(result).to eq([])
      end
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
