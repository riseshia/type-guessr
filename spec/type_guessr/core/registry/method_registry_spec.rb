# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/registry/method_registry"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::Registry::MethodRegistry do
  let(:registry) { described_class.new }

  # Create a mock DefNode for testing
  def create_def_node(name)
    TypeGuessr::Core::IR::DefNode.new(name.to_sym, nil, [], nil, [], [], nil, false)
  end

  describe "#register and #lookup" do
    it "stores and retrieves method definitions" do
      def_node = create_def_node("my_method")
      registry.register("MyClass", "my_method", def_node)

      result = registry.lookup("MyClass", "my_method")
      expect(result).to eq(def_node)
    end

    it "returns nil for unknown method" do
      result = registry.lookup("MyClass", "unknown_method")
      expect(result).to be_nil
    end

    it "returns nil for unknown class" do
      result = registry.lookup("UnknownClass", "my_method")
      expect(result).to be_nil
    end

    it "overwrites existing method with same name" do
      old_node = create_def_node("my_method")
      new_node = create_def_node("my_method")
      registry.register("MyClass", "my_method", old_node)
      registry.register("MyClass", "my_method", new_node)

      result = registry.lookup("MyClass", "my_method")
      expect(result).to eq(new_node)
    end

    context "with code_index" do
      let(:code_index) do
        double.tap do |idx|
          allow(idx).to receive(:ancestors_of).and_return([])
          allow(idx).to receive(:ancestors_of).with("Child").and_return(%w[Child Parent GrandParent])
          allow(idx).to receive(:ancestors_of).with("Parent").and_return(%w[Parent GrandParent])
          allow(idx).to receive(:ancestors_of).with("GrandParent").and_return(["GrandParent"])
        end
      end

      let(:registry) { described_class.new(code_index: code_index) }

      it "finds method in parent class" do
        parent_method = create_def_node("parent_method")
        registry.register("Parent", "parent_method", parent_method)

        result = registry.lookup("Child", "parent_method")
        expect(result).to eq(parent_method)
      end

      it "finds method in grandparent class" do
        grandparent_method = create_def_node("gp_method")
        registry.register("GrandParent", "gp_method", grandparent_method)

        result = registry.lookup("Child", "gp_method")
        expect(result).to eq(grandparent_method)
      end

      it "prefers child method over parent method" do
        parent_method = create_def_node("shared_method")
        child_method = create_def_node("shared_method")
        registry.register("Parent", "shared_method", parent_method)
        registry.register("Child", "shared_method", child_method)

        result = registry.lookup("Child", "shared_method")
        expect(result).to eq(child_method)
      end
    end
  end

  describe "#methods_for_class" do
    it "returns empty hash for unknown class" do
      expect(registry.methods_for_class("UnknownClass")).to eq({})
    end

    it "returns methods hash for class" do
      method1 = create_def_node("method1")
      method2 = create_def_node("method2")
      registry.register("MyClass", "method1", method1)
      registry.register("MyClass", "method2", method2)

      result = registry.methods_for_class("MyClass")
      expect(result).to eq({ "method1" => method1, "method2" => method2 })
    end

    it "returns frozen hash" do
      registry.register("MyClass", "method1", create_def_node("method1"))

      expect(registry.methods_for_class("MyClass")).to be_frozen
    end
  end

  describe "#search" do
    before do
      registry.register("User", "find", create_def_node("find"))
      registry.register("User", "find_by_id", create_def_node("find_by_id"))
      registry.register("Post", "find", create_def_node("find"))
      registry.register("Comment", "create", create_def_node("create"))
    end

    it "finds methods matching pattern in full name" do
      results = registry.search("User#find")

      expect(results.size).to eq(2)
      expect(results.map { |r| r[1] }).to contain_exactly("find", "find_by_id")
    end

    it "finds methods matching class pattern" do
      results = registry.search("User#")

      expect(results.size).to eq(2)
      expect(results.map { |r| r[0] }).to all(eq("User"))
    end

    it "finds methods matching method name pattern" do
      results = registry.search("#find")

      expect(results.size).to eq(3)
      expect(results.map { |r| r[1] }).to contain_exactly("find", "find", "find_by_id")
    end

    it "returns empty array when no match" do
      results = registry.search("NonExistent")

      expect(results).to eq([])
    end
  end

  describe "#each_entry" do
    it "yields all registered methods" do
      method1 = create_def_node("method1")
      method2 = create_def_node("method2")
      method3 = create_def_node("create")
      registry.register("User", "method1", method1)
      registry.register("User", "method2", method2)
      registry.register("Post", "create", method3)

      entries = []
      registry.each_entry { |cn, mn, dn| entries << [cn, mn, dn] }

      expect(entries).to contain_exactly(
        ["User", "method1", method1],
        ["User", "method2", method2],
        ["Post", "create", method3]
      )
    end

    it "returns an enumerator when no block given" do
      registry.register("User", "find", create_def_node("find"))

      enum = registry.each_entry

      expect(enum).to be_a(Enumerator)
      expect(enum.to_a.size).to eq(1)
    end

    it "returns empty enumerator when registry is empty" do
      expect(registry.each_entry.to_a).to be_empty
    end
  end

  describe "#clear" do
    it "removes all registered methods" do
      registry.register("MyClass", "method1", create_def_node("method1"))
      registry.clear

      expect(registry.methods_for_class("MyClass")).to eq({})
      expect(registry.lookup("MyClass", "method1")).to be_nil
    end
  end

  describe "#code_index=" do
    it "allows setting code_index after initialization" do
      parent_method = create_def_node("parent_method")
      registry.register("Parent", "parent_method", parent_method)

      # Initially, cannot find via inheritance
      expect(registry.lookup("Child", "parent_method")).to be_nil

      # Set code_index
      code_index = double
      allow(code_index).to receive(:ancestors_of).and_return([])
      allow(code_index).to receive(:ancestors_of).with("Child").and_return(%w[Child Parent])
      registry.code_index = code_index

      # Now can find via inheritance
      expect(registry.lookup("Child", "parent_method")).to eq(parent_method)
    end
  end
end
