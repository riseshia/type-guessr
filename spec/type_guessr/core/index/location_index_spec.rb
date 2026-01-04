# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/index/location_index"
require "type_guessr/core/ir/nodes"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::Index::LocationIndex do
  let(:index) { described_class.new }
  let(:file_path) { "/path/to/file.rb" }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }

  describe "#add and #find" do
    it "indexes and finds a node by location" do
      node = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 10...20)
      )

      index.add(file_path, node)
      index.finalize!

      found = index.find(file_path, 5, 15)
      expect(found).to eq(node)
    end

    it "returns nil when position is not found" do
      node = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 10...20)
      )

      index.add(file_path, node)
      index.finalize!

      # Different line
      expect(index.find(file_path, 6, 15)).to be_nil

      # Outside column range
      expect(index.find(file_path, 5, 5)).to be_nil
      expect(index.find(file_path, 5, 25)).to be_nil
    end

    it "returns nil when file is not indexed" do
      expect(index.find("/other/file.rb", 1, 0)).to be_nil
    end

    it "finds the most specific node when multiple nodes overlap" do
      # Outer node (wider range)
      outer = TypeGuessr::Core::IR::CallNode.new(
        method: :foo,
        receiver: nil,
        args: [],
        block_params: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...20)
      )

      # Inner node (narrower range)
      inner = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 5...10)
      )

      index.add(file_path, outer)
      index.add(file_path, inner)
      index.finalize!

      # Position within inner range should return inner node
      found = index.find(file_path, 1, 7)
      expect(found).to eq(inner)

      # Position outside inner range but inside outer range should return outer node
      found = index.find(file_path, 1, 15)
      expect(found).to eq(outer)
    end

    it "ignores nodes without location" do
      node_without_loc = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: nil
      )

      index.add(file_path, node_without_loc)
      index.finalize!

      expect(index.find(file_path, 1, 0)).to be_nil
    end
  end

  describe "#nodes_for_file" do
    it "returns all nodes for a file" do
      node1 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 2, col_range: 0...5)
      )

      index.add(file_path, node1)
      index.add(file_path, node2)

      nodes = index.nodes_for_file(file_path)
      expect(nodes).to contain_exactly(node1, node2)
    end

    it "returns empty array for non-existent file" do
      expect(index.nodes_for_file("/other/file.rb")).to eq([])
    end
  end

  describe "#remove_file" do
    it "removes all entries for a file" do
      node = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node)
      index.finalize!

      expect(index.find(file_path, 1, 2)).to eq(node)

      index.remove_file(file_path)
      expect(index.find(file_path, 1, 2)).to be_nil
    end
  end

  describe "#clear" do
    it "clears all indexed data" do
      node1 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node1)
      index.add("/other/file.rb", node2)
      index.finalize!

      index.clear

      expect(index.find(file_path, 1, 2)).to be_nil
      expect(index.find("/other/file.rb", 1, 2)).to be_nil
    end
  end

  describe "#stats" do
    it "returns statistics about the index" do
      node1 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )
      node2 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 2, col_range: 0...5)
      )
      node3 = TypeGuessr::Core::IR::LiteralNode.new(
        type: string_type,
        loc: TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...5)
      )

      index.add(file_path, node1)
      index.add(file_path, node2)
      index.add("/other/file.rb", node3)

      stats = index.stats
      expect(stats[:files_count]).to eq(2)
      expect(stats[:total_nodes]).to eq(3)
    end
  end
end
