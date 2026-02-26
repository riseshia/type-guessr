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

  describe "#remove_file" do
    it "removes variables registered from a specific file" do
      node_a = create_cvar_write_node(:@@count, "Counter")
      node_b = create_cvar_write_node(:@@total, "Counter")
      registry.register("Counter", :@@count, node_a, file_path: "/app/counter.rb")
      registry.register("Counter", :@@total, node_b, file_path: "/app/stats.rb")

      registry.remove_file("/app/counter.rb")

      expect(registry.lookup("Counter", :@@count)).to be_nil
      expect(registry.lookup("Counter", :@@total)).to eq(node_b)
    end

    it "cleans up empty class entries" do
      node = create_cvar_write_node(:@@count, "OnlyClass")
      registry.register("OnlyClass", :@@count, node, file_path: "/app/only.rb")

      registry.remove_file("/app/only.rb")

      expect(registry.lookup("OnlyClass", :@@count)).to be_nil
    end

    it "is no-op for unknown file" do
      node = create_cvar_write_node(:@@count, "Counter")
      registry.register("Counter", :@@count, node, file_path: "/app/counter.rb")

      registry.remove_file("/app/unknown.rb")

      expect(registry.lookup("Counter", :@@count)).to eq(node)
    end

    it "does not track no-op registrations (first write wins)" do
      node_a = create_cvar_write_node(:@@count, "Counter")
      node_b = create_cvar_write_node(:@@count, "Counter")
      registry.register("Counter", :@@count, node_a, file_path: "/app/a.rb")
      registry.register("Counter", :@@count, node_b, file_path: "/app/b.rb") # no-op

      registry.remove_file("/app/b.rb") # should have no effect

      expect(registry.lookup("Counter", :@@count)).to eq(node_a)
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
