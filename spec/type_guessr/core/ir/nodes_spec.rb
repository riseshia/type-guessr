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
      node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      expect(node.type).to eq(string_type)
      expect(node.loc).to eq(loc)
    end

    it "has no dependencies when values is nil" do
      node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      expect(node.dependencies).to eq([])
    end

    it "returns values as dependencies when present" do
      inner1 = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      inner2 = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      array_type = TypeGuessr::Core::Types::ArrayType.new(string_type)
      node = described_class::LiteralNode.new(
        type: array_type,
        literal_value: nil,
        values: [inner1, inner2],
        loc: loc
      )
      expect(node.dependencies).to eq([inner1, inner2])
    end

    it "returns empty array when values is empty" do
      node = described_class::LiteralNode.new(
        type: TypeGuessr::Core::Types::ArrayType.new,
        literal_value: nil,
        values: [],
        loc: loc
      )
      expect(node.dependencies).to eq([])
    end
  end

  describe "LocalWriteNode" do
    it "stores write variable information" do
      literal = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::LocalWriteNode.new(
        name: :user,
        value: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:user)
      expect(node.value).to eq(literal)
      expect(node.called_methods).to eq([])
    end

    it "returns value in dependencies array" do
      literal = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::LocalWriteNode.new(
        name: :user,
        value: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([literal])
    end

    it "shares called_methods array for mutation" do
      methods = []
      node = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: methods,
        loc: loc
      )

      # Mutate the shared array
      methods << :profile
      expect(node.called_methods).to eq([:profile])
    end

    it "generates local_write node_hash" do
      literal = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::LocalWriteNode.new(
        name: :user,
        value: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("local_write:user:1")
    end
  end

  describe "InstanceVariableWriteNode" do
    it "stores instance variable information" do
      literal = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::InstanceVariableWriteNode.new(
        name: :@user,
        class_name: "User",
        value: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:@user)
      expect(node.class_name).to eq("User")
      expect(node.value).to eq(literal)
    end

    it "generates ivar_write node_hash" do
      node = described_class::InstanceVariableWriteNode.new(
        name: :@user,
        class_name: "User",
        value: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("ivar_write:@user:1")
    end
  end

  describe "ClassVariableWriteNode" do
    it "stores class variable information" do
      literal = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::ClassVariableWriteNode.new(
        name: :@@count,
        class_name: "Counter",
        value: literal,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:@@count)
      expect(node.class_name).to eq("Counter")
      expect(node.value).to eq(literal)
    end

    it "generates cvar_write node_hash" do
      node = described_class::ClassVariableWriteNode.new(
        name: :@@count,
        class_name: "Counter",
        value: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("cvar_write:@@count:1")
    end
  end

  describe "LocalReadNode" do
    it "stores read variable information" do
      write_node = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::LocalReadNode.new(
        name: :user,
        write_node: write_node,
        called_methods: write_node.called_methods,
        loc: loc
      )

      expect(node.name).to eq(:user)
      expect(node.write_node).to eq(write_node)
    end

    it "returns write_node in dependencies array" do
      write_node = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::LocalReadNode.new(
        name: :user,
        write_node: write_node,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([write_node])
    end

    it "shares called_methods with write_node" do
      methods = []
      write_node = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: methods,
        loc: loc
      )
      node = described_class::LocalReadNode.new(
        name: :user,
        write_node: write_node,
        called_methods: methods,
        loc: loc
      )

      # Mutate via write_node
      methods << :profile
      expect(node.called_methods).to eq([:profile])
    end

    it "generates local_read node_hash" do
      write_node = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::LocalReadNode.new(
        name: :user,
        write_node: write_node,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("local_read:user:1")
    end
  end

  describe "InstanceVariableReadNode" do
    it "stores instance variable read information" do
      write_node = described_class::InstanceVariableWriteNode.new(
        name: :@user,
        class_name: "User",
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::InstanceVariableReadNode.new(
        name: :@user,
        class_name: "User",
        write_node: write_node,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:@user)
      expect(node.class_name).to eq("User")
      expect(node.write_node).to eq(write_node)
    end

    it "generates ivar_read node_hash" do
      node = described_class::InstanceVariableReadNode.new(
        name: :@user,
        class_name: "User",
        write_node: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("ivar_read:@user:1")
    end
  end

  describe "ClassVariableReadNode" do
    it "stores class variable read information" do
      write_node = described_class::ClassVariableWriteNode.new(
        name: :@@count,
        class_name: "Counter",
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::ClassVariableReadNode.new(
        name: :@@count,
        class_name: "Counter",
        write_node: write_node,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:@@count)
      expect(node.class_name).to eq("Counter")
      expect(node.write_node).to eq(write_node)
    end

    it "generates cvar_read node_hash" do
      node = described_class::ClassVariableReadNode.new(
        name: :@@count,
        class_name: "Counter",
        write_node: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.node_hash).to eq("cvar_read:@@count:1")
    end
  end

  describe "ParamNode" do
    it "stores parameter information" do
      default = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::ParamNode.new(
        name: :name,
        kind: :optional,
        default_value: default,
        called_methods: [],
        loc: loc
      )

      expect(node.name).to eq(:name)
      expect(node.kind).to eq(:optional)
      expect(node.default_value).to eq(default)
    end

    it "returns default_value in dependencies when present" do
      default = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::ParamNode.new(
        name: :name,
        kind: :optional,
        default_value: default,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([default])
    end

    it "returns empty dependencies when no default_value" do
      node = described_class::ParamNode.new(
        name: :name,
        kind: :required,
        default_value: nil,
        called_methods: [],
        loc: loc
      )

      expect(node.dependencies).to eq([])
    end
  end

  describe "CallNode" do
    it "stores call information" do
      receiver = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: [],
        loc: loc
      )
      node = described_class::CallNode.new(
        method: :profile,
        receiver: receiver,
        args: [],
        block_params: [],
        block_body: nil,
        has_block: false,
        loc: loc
      )

      expect(node.method).to eq(:profile)
      expect(node.receiver).to eq(receiver)
      expect(node.args).to eq([])
    end

    it "includes receiver and args in dependencies" do
      receiver = described_class::LocalWriteNode.new(
        name: :user,
        value: nil,
        called_methods: [],
        loc: loc
      )
      arg = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      node = described_class::CallNode.new(
        method: :update,
        receiver: receiver,
        args: [arg],
        block_params: [],
        block_body: nil,
        has_block: false,
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
        block_body: nil,
        has_block: true,
        loc: loc
      )
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call, loc: loc)

      expect(slot.index).to eq(0)
      expect(slot.call_node).to eq(call)
    end

    it "returns call_node in dependencies" do
      call = described_class::CallNode.new(
        method: :each,
        receiver: nil,
        args: [],
        block_params: [],
        block_body: nil,
        has_block: true,
        loc: loc
      )
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call, loc: loc)

      expect(slot.dependencies).to eq([call])
    end

    it "has its own loc" do
      call = described_class::CallNode.new(
        method: :each,
        receiver: nil,
        args: [],
        block_params: [],
        block_body: nil,
        has_block: true,
        loc: loc
      )
      slot_loc = described_class::Loc.new(line: 1, col_range: 10...15)
      slot = described_class::BlockParamSlot.new(index: 0, call_node: call, loc: slot_loc)

      expect(slot.loc).to eq(slot_loc)
    end
  end

  describe "MergeNode" do
    it "stores branch nodes" do
      then_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      else_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      merge = described_class::MergeNode.new(
        branches: [then_node, else_node],
        loc: loc
      )

      expect(merge.branches).to eq([then_node, else_node])
    end

    it "returns branches as dependencies" do
      then_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      else_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
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
        kind: :required,
        default_value: nil,
        called_methods: [],
        loc: loc
      )
      return_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      def_node = described_class::DefNode.new(
        name: :foo,
        params: [param],
        return_node: return_node,
        body_nodes: [return_node],
        loc: loc
      )

      expect(def_node.name).to eq(:foo)
      expect(def_node.params).to eq([param])
      expect(def_node.return_node).to eq(return_node)
    end

    it "includes params, return_node, and body_nodes in dependencies" do
      param = described_class::ParamNode.new(
        name: :x,
        kind: :required,
        default_value: nil,
        called_methods: [],
        loc: loc
      )
      return_node = described_class::LiteralNode.new(type: string_type, literal_value: nil, values: nil, loc: loc)
      def_node = described_class::DefNode.new(
        name: :foo,
        params: [param],
        return_node: return_node,
        body_nodes: [return_node],
        loc: loc
      )

      # param, return_node, and body_nodes (which contains return_node again)
      expect(def_node.dependencies).to include(param)
      expect(def_node.dependencies).to include(return_node)
      expect(def_node.dependencies.count(return_node)).to eq(2) # once in return_node, once in body_nodes
    end
  end
end
