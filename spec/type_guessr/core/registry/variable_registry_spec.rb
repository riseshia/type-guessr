# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/registry/variable_registry"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::Registry::VariableRegistry do
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

  # Create a mock ClassVariableWriteNode for testing
  def create_cvar_write_node(name, class_name = nil)
    TypeGuessr::Core::IR::ClassVariableWriteNode.new(
      name: name,
      class_name: class_name,
      value: nil,
      called_methods: [],
      loc: nil
    )
  end

  describe "#register_instance_variable and #lookup_instance_variable" do
    it "stores and retrieves instance variable definitions" do
      write_node = create_ivar_write_node(:@recipe, "User")
      registry.register_instance_variable("User", :@recipe, write_node)

      result = registry.lookup_instance_variable("User", :@recipe)
      expect(result).to eq(write_node)
    end

    it "returns nil for unknown instance variable" do
      result = registry.lookup_instance_variable("User", :@unknown)
      expect(result).to be_nil
    end

    it "returns nil for unknown class" do
      result = registry.lookup_instance_variable("UnknownClass", :@name)
      expect(result).to be_nil
    end

    it "returns nil when class_name is nil" do
      registry.register_instance_variable(nil, :@name, create_ivar_write_node(:@name))
      result = registry.lookup_instance_variable(nil, :@name)
      expect(result).to be_nil
    end

    it "first write wins (does not overwrite)" do
      old_node = create_ivar_write_node(:@recipe, "User")
      new_node = create_ivar_write_node(:@recipe, "User")
      registry.register_instance_variable("User", :@recipe, old_node)
      registry.register_instance_variable("User", :@recipe, new_node)

      result = registry.lookup_instance_variable("User", :@recipe)
      expect(result).to eq(old_node)
    end

    context "with ancestry_provider" do
      let(:ancestry_provider) do
        lambda do |class_name|
          case class_name
          when "Child" then %w[Child Parent GrandParent]
          when "Parent" then %w[Parent GrandParent]
          when "GrandParent" then ["GrandParent"]
          else []
          end
        end
      end

      let(:registry) { described_class.new(ancestry_provider: ancestry_provider) }

      it "finds instance variable in parent class" do
        parent_ivar = create_ivar_write_node(:@name, "Parent")
        registry.register_instance_variable("Parent", :@name, parent_ivar)

        result = registry.lookup_instance_variable("Child", :@name)
        expect(result).to eq(parent_ivar)
      end

      it "finds instance variable in grandparent class" do
        grandparent_ivar = create_ivar_write_node(:@id, "GrandParent")
        registry.register_instance_variable("GrandParent", :@id, grandparent_ivar)

        result = registry.lookup_instance_variable("Child", :@id)
        expect(result).to eq(grandparent_ivar)
      end

      it "prefers child instance variable over parent" do
        parent_ivar = create_ivar_write_node(:@name, "Parent")
        child_ivar = create_ivar_write_node(:@name, "Child")
        registry.register_instance_variable("Parent", :@name, parent_ivar)
        registry.register_instance_variable("Child", :@name, child_ivar)

        result = registry.lookup_instance_variable("Child", :@name)
        expect(result).to eq(child_ivar)
      end
    end
  end

  describe "#register_class_variable and #lookup_class_variable" do
    it "stores and retrieves class variable definitions" do
      write_node = create_cvar_write_node(:@@count, "Counter")
      registry.register_class_variable("Counter", :@@count, write_node)

      result = registry.lookup_class_variable("Counter", :@@count)
      expect(result).to eq(write_node)
    end

    it "returns nil for unknown class variable" do
      result = registry.lookup_class_variable("Counter", :@@unknown)
      expect(result).to be_nil
    end

    it "returns nil for unknown class" do
      result = registry.lookup_class_variable("UnknownClass", :@@count)
      expect(result).to be_nil
    end

    it "returns nil when class_name is nil" do
      registry.register_class_variable(nil, :@@count, create_cvar_write_node(:@@count))
      result = registry.lookup_class_variable(nil, :@@count)
      expect(result).to be_nil
    end

    it "first write wins (does not overwrite)" do
      old_node = create_cvar_write_node(:@@count, "Counter")
      new_node = create_cvar_write_node(:@@count, "Counter")
      registry.register_class_variable("Counter", :@@count, old_node)
      registry.register_class_variable("Counter", :@@count, new_node)

      result = registry.lookup_class_variable("Counter", :@@count)
      expect(result).to eq(old_node)
    end
  end

  describe "#clear" do
    it "removes all registered variables" do
      registry.register_instance_variable("User", :@name, create_ivar_write_node(:@name, "User"))
      registry.register_class_variable("Counter", :@@count, create_cvar_write_node(:@@count, "Counter"))

      registry.clear

      expect(registry.lookup_instance_variable("User", :@name)).to be_nil
      expect(registry.lookup_class_variable("Counter", :@@count)).to be_nil
    end
  end

  describe "#ancestry_provider=" do
    it "allows setting ancestry_provider after initialization" do
      parent_ivar = create_ivar_write_node(:@name, "Parent")
      registry.register_instance_variable("Parent", :@name, parent_ivar)

      # Initially, cannot find via inheritance
      expect(registry.lookup_instance_variable("Child", :@name)).to be_nil

      # Set ancestry provider
      registry.ancestry_provider = ->(name) { name == "Child" ? %w[Child Parent] : [name] }

      # Now can find via inheritance
      expect(registry.lookup_instance_variable("Child", :@name)).to eq(parent_ivar)
    end
  end
end
