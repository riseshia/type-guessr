# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/index/location_index"
require "type_guessr/core/ir/nodes"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::Index::LocationIndex do
  let(:index) { described_class.new }
  let(:file_path) { "/path/to/file.rb" }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }

  describe "#add and #find_by_key" do
    it "indexes and finds a node by key" do
      node = TypeGuessr::Core::IR::VariableNode.new(
        name: :name,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 10...20)
      )

      index.add(file_path, node, "User#save")
      index.finalize!

      # node_key = "User#save:var:name:5"
      found = index.find_by_key("User#save:var:name:5")
      expect(found).to eq(node)
    end

    it "returns nil when key is not found" do
      node = TypeGuessr::Core::IR::VariableNode.new(
        name: :name,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 10...20)
      )

      index.add(file_path, node, "User#save")
      index.finalize!

      # Different scope
      expect(index.find_by_key("Admin#update:var:name:5")).to be_nil

      # Different variable
      expect(index.find_by_key("User#save:var:title:5")).to be_nil

      # Different line
      expect(index.find_by_key("User#save:var:name:10")).to be_nil
    end

    it "works with empty scope_id" do
      node = TypeGuessr::Core::IR::VariableNode.new(
        name: :x,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node, "")

      # node_key = ":var:x:1"
      found = index.find_by_key(":var:x:1")
      expect(found).to eq(node)
    end

    it "ignores nodes without location" do
      node_without_loc = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: nil
      )

      index.add(file_path, node_without_loc)
      index.finalize!

      expect(index.find_by_key(":lit:ClassInstance:1")).to be_nil
    end
  end

  describe "#nodes_for_file" do
    it "returns all nodes for a file" do
      node1 = TypeGuessr::Core::IR::VariableNode.new(
        name: :x,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::VariableNode.new(
        name: :y,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 2, col_range: 0...5)
      )

      index.add(file_path, node1, "")
      index.add(file_path, node2, "")

      nodes = index.nodes_for_file(file_path)
      expect(nodes).to contain_exactly(node1, node2)
    end

    it "returns empty array for non-existent file" do
      expect(index.nodes_for_file("/other/file.rb")).to eq([])
    end
  end

  describe "#remove_file" do
    it "removes all entries for a file" do
      node = TypeGuessr::Core::IR::VariableNode.new(
        name: :name,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node, "User#save")
      index.finalize!

      expect(index.find_by_key("User#save:var:name:1")).to eq(node)

      index.remove_file(file_path)
      expect(index.find_by_key("User#save:var:name:1")).to be_nil
    end
  end

  describe "#clear" do
    it "clears all indexed data" do
      node1 = TypeGuessr::Core::IR::VariableNode.new(
        name: :x,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::VariableNode.new(
        name: :y,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node1, "A#m")
      index.add("/other/file.rb", node2, "B#n")
      index.finalize!

      index.clear

      expect(index.find_by_key("A#m:var:x:1")).to be_nil
      expect(index.find_by_key("B#n:var:y:1")).to be_nil
    end
  end

  describe "#stats" do
    it "returns statistics about the index" do
      node1 = TypeGuessr::Core::IR::VariableNode.new(
        name: :x,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::VariableNode.new(
        name: :y,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 2, col_range: 0...5)
      )
      node3 = TypeGuessr::Core::IR::VariableNode.new(
        name: :z,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node1, "")
      index.add(file_path, node2, "")
      index.add("/other/file.rb", node3, "")

      stats = index.stats
      expect(stats[:files_count]).to eq(2)
      expect(stats[:total_nodes]).to eq(3)
    end
  end
end
