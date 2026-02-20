# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/registry/class_variable_registry"
require "type_guessr/core/ir/nodes"

RSpec.describe TypeGuessr::Core::Registry::ClassVariableRegistry do
  let(:registry) { described_class.new }

  # Create a mock ClassVariableWriteNode for testing
  def create_cvar_write_node(name, class_name = nil)
    TypeGuessr::Core::IR::ClassVariableWriteNode.new(name, class_name, nil, [], nil)
  end

  describe "#register and #lookup" do
    it "stores and retrieves class variable definitions" do
      write_node = create_cvar_write_node(:@@count, "Counter")
      registry.register("Counter", :@@count, write_node)

      result = registry.lookup("Counter", :@@count)
      expect(result).to eq(write_node)
    end

    it "returns nil for unknown class variable" do
      result = registry.lookup("Counter", :@@unknown)
      expect(result).to be_nil
    end

    it "returns nil for unknown class" do
      result = registry.lookup("UnknownClass", :@@count)
      expect(result).to be_nil
    end

    it "returns nil when class_name is nil" do
      registry.register(nil, :@@count, create_cvar_write_node(:@@count))
      result = registry.lookup(nil, :@@count)
      expect(result).to be_nil
    end

    it "first write wins (does not overwrite)" do
      old_node = create_cvar_write_node(:@@count, "Counter")
      new_node = create_cvar_write_node(:@@count, "Counter")
      registry.register("Counter", :@@count, old_node)
      registry.register("Counter", :@@count, new_node)

      result = registry.lookup("Counter", :@@count)
      expect(result).to eq(old_node)
    end
  end

  describe "#clear" do
    it "removes all registered variables" do
      registry.register("Counter", :@@count, create_cvar_write_node(:@@count, "Counter"))

      registry.clear

      expect(registry.lookup("Counter", :@@count)).to be_nil
    end
  end
end
