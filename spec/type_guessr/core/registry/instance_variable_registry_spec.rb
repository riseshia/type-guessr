# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/registry/instance_variable_registry"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::Registry::InstanceVariableRegistry do
  let(:registry) { described_class.new }

  # Create a mock InstanceVariableWriteNode for testing
  def create_ivar_write_node(name, class_name = nil)
    TypeGuessr::Core::IR::InstanceVariableWriteNode.new(
      name: name,
      class_name: class_name,
      value: nil,
      called_methods: [],
      loc: nil
    )
  end

  describe "#register and #lookup" do
    it "stores and retrieves instance variable definitions" do
      write_node = create_ivar_write_node(:@recipe, "User")
      registry.register("User", :@recipe, write_node)

      result = registry.lookup("User", :@recipe)
      expect(result).to eq(write_node)
    end

    it "returns nil for unknown instance variable" do
      result = registry.lookup("User", :@unknown)
      expect(result).to be_nil
    end

    it "returns nil for unknown class" do
      result = registry.lookup("UnknownClass", :@name)
      expect(result).to be_nil
    end

    it "returns nil when class_name is nil" do
      registry.register(nil, :@name, create_ivar_write_node(:@name))
      result = registry.lookup(nil, :@name)
      expect(result).to be_nil
    end

    it "first write wins (does not overwrite)" do
      old_node = create_ivar_write_node(:@recipe, "User")
      new_node = create_ivar_write_node(:@recipe, "User")
      registry.register("User", :@recipe, old_node)
      registry.register("User", :@recipe, new_node)

      result = registry.lookup("User", :@recipe)
      expect(result).to eq(old_node)
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

      it "finds instance variable in parent class" do
        parent_ivar = create_ivar_write_node(:@name, "Parent")
        registry.register("Parent", :@name, parent_ivar)

        result = registry.lookup("Child", :@name)
        expect(result).to eq(parent_ivar)
      end

      it "finds instance variable in grandparent class" do
        grandparent_ivar = create_ivar_write_node(:@id, "GrandParent")
        registry.register("GrandParent", :@id, grandparent_ivar)

        result = registry.lookup("Child", :@id)
        expect(result).to eq(grandparent_ivar)
      end

      it "prefers child instance variable over parent" do
        parent_ivar = create_ivar_write_node(:@name, "Parent")
        child_ivar = create_ivar_write_node(:@name, "Child")
        registry.register("Parent", :@name, parent_ivar)
        registry.register("Child", :@name, child_ivar)

        result = registry.lookup("Child", :@name)
        expect(result).to eq(child_ivar)
      end
    end
  end

  describe "#clear" do
    it "removes all registered variables" do
      registry.register("User", :@name, create_ivar_write_node(:@name, "User"))

      registry.clear

      expect(registry.lookup("User", :@name)).to be_nil
    end
  end

  describe "#code_index=" do
    it "allows setting code_index after initialization" do
      parent_ivar = create_ivar_write_node(:@name, "Parent")
      registry.register("Parent", :@name, parent_ivar)

      # Initially, cannot find via inheritance
      expect(registry.lookup("Child", :@name)).to be_nil

      # Set code_index
      code_index = double
      allow(code_index).to receive(:ancestors_of).and_return([])
      allow(code_index).to receive(:ancestors_of).with("Child").and_return(%w[Child Parent])
      registry.code_index = code_index

      # Now can find via inheritance
      expect(registry.lookup("Child", :@name)).to eq(parent_ivar)
    end
  end
end
