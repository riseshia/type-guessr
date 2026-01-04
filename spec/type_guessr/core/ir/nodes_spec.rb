# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/ir/nodes"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::IR do
  let(:loc) { described_class::Loc.new(line: 1, col_range: 0...10) }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }

  describe "Loc" do
    it "stores line and column range" do
      loc = described_class::Loc.new(line: 5, col_range: 10...20)
      expect(loc.line).to eq(5)
      expect(loc.col_range).to eq(10...20)
    end
  end

  describe "LiteralNode" do
    it "stores type and location" do
      node = described_class::LiteralNode.new(type: string_type, loc: loc)
      expect(node.type).to eq(string_type)
      expect(node.loc).to eq(loc)
    end

    it "has no dependencies (leaf node)" do
      node = described_class::LiteralNode.new(type: string_type, loc: loc)
      expect(node.dependencies).to eq([])
    end
  end

  describe "VariableNode" do
    it "stores variable information" do
      literal = described_class::LiteralNode.new(type: string_type, loc: loc)
      node = described_class::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:user)
      expect(node.kind).to eq(:local)
      expect(node.dependency).to eq(literal)
      expect(node.called_methods).to eq([])
    end

    it "returns dependency in dependencies array" do
      literal = described_class::LiteralNode.new(type: string_type, loc: loc)
      node = described_class::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([literal])
    end

    it "shares called_methods array for mutation" do
      methods = []
      node = described_class::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: nil,
        called_methods: methods,
        loc: loc
      )

      # Mutate the shared array
      methods << :profile
      expect(node.called_methods).to eq([:profile])
    end
  end

  describe "ParamNode" do
    it "stores parameter information" do
      default = described_class::LiteralNode.new(type: string_type, loc: loc)
      node = described_class::ParamNode.new(
        name: :name,
        default_value: default,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:name)
      expect(node.default_value).to eq(default)
    end

    it "returns default_value in dependencies when present" do
      default = described_class::LiteralNode.new(type: string_type, loc: loc)
      node = described_class::ParamNode.new(
        name: :name,
        default_value: default,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([default])
    end

    it "returns empty dependencies when no default_value" do
      node = described_class::ParamNode.new(
        name: :name,
        default_value: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([])
    end
  end

  describe "CallNode" do
    it "stores call information" do
      receiver = described_class::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::CallNode.new(
        method: :profile,
        receiver: receiver,
        args: [],
        block_params: [],
        loc: loc
      )

      expect(node.method).to eq(:profile)
      expect(node.receiver).to eq(receiver)
      expect(node.args).to eq([])
    end

    it "includes receiver and args in dependencies" do
      receiver = described_class::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: loc
      )
      arg = described_class::LiteralNode.new(type: string_type, loc: loc)
      node = described_class::CallNode.new(
        method: :update,
        receiver: receiver,
        args: [arg],
        block_params: [],
        loc: loc
      )

      expect(node.dependencies).to contain_exactly(receiver, arg)
    end
  end

  describe "BlockParamSlot" do
    it "stores block parameter information" do
      call = described_class::CallNode.new(
        method: :each,
        receiver: nil,
        args: [],
        block_params: [],
        loc: loc
      )
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call)

      expect(slot.index).to eq(0)
      expect(slot.call_node).to eq(call)
    end

    it "returns call_node in dependencies" do
      call = described_class::CallNode.new(
        method: :each,
        receiver: nil,
        args: [],
        block_params: [],
        loc: loc
      )
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call)

      expect(slot.dependencies).to eq([call])
    end

    it "delegates loc to call_node" do
      call = described_class::CallNode.new(
        method: :each,
        receiver: nil,
        args: [],
        block_params: [],
        loc: loc
      )
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call)

      expect(slot.loc).to eq(loc)
    end
  end

  describe "MergeNode" do
    it "stores branch nodes" do
      then_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      else_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      merge = described_class::MergeNode.new(
        branches: [then_node, else_node],
        loc: loc
      )

      expect(merge.branches).to eq([then_node, else_node])
    end

    it "returns branches as dependencies" do
      then_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      else_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      merge = described_class::MergeNode.new(
        branches: [then_node, else_node],
        loc: loc
      )

      expect(merge.dependencies).to eq([then_node, else_node])
    end
  end

  describe "DefNode" do
    it "stores method definition information" do
      param = described_class::ParamNode.new(
        name: :x,
        default_value: nil,
        called_methods: [],
        loc: loc
      )
      return_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      def_node = described_class::DefNode.new(
        name: :foo,
        params: [param],
        return_node: return_node,
        loc: loc
      )

      expect(def_node.name).to eq(:foo)
      expect(def_node.params).to eq([param])
      expect(def_node.return_node).to eq(return_node)
    end

    it "includes params and return_node in dependencies" do
      param = described_class::ParamNode.new(
        name: :x,
        default_value: nil,
        called_methods: [],
        loc: loc
      )
      return_node = described_class::LiteralNode.new(type: string_type, loc: loc)
      def_node = described_class::DefNode.new(
        name: :foo,
        params: [param],
        return_node: return_node,
        loc: loc
      )

      expect(def_node.dependencies).to contain_exactly(param, return_node)
    end
  end
end
