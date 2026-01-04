# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/inference/resolver"
require "type_guessr/core/rbs_provider"

RSpec.describe TypeGuessr::Core::Inference::Resolver do
  let(:rbs_provider) { TypeGuessr::Core::RBSProvider.instance }
  let(:resolver) { described_class.new(rbs_provider) }
  let(:loc) { TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...10) }

  describe "#infer" do
    context "with nil node" do
      it "returns Unknown" do
        result = resolver.infer(nil)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("no node")
      end
    end

    context "with LiteralNode" do
      it "returns the literal type" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )

        result = resolver.infer(node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to eq("literal")
        expect(result.source).to eq(:literal)
      end
    end

    context "with VariableNode" do
      it "infers type from dependency" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          loc: loc
        )
        var_node = TypeGuessr::Core::IR::VariableNode.new(
          name: :x,
          kind: :local,
          dependency: literal,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(var_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to eq("assigned from literal")
      end

      it "returns Unknown for unassigned variable" do
        var_node = TypeGuessr::Core::IR::VariableNode.new(
          name: :x,
          kind: :local,
          dependency: nil,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(var_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unassigned variable")
      end
    end

    context "with ParamNode" do
      it "infers type from default value" do
        default = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
        param = TypeGuessr::Core::IR::ParamNode.new(
          name: :name,
          default_value: default,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(param)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("parameter default")
      end

      it "returns Unknown for parameter without default or methods" do
        param = TypeGuessr::Core::IR::ParamNode.new(
          name: :x,
          default_value: nil,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(param)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("parameter without type info")
      end

      it "records called methods for duck typing" do
        param = TypeGuessr::Core::IR::ParamNode.new(
          name: :recipe,
          default_value: nil,
          called_methods: %i[comments title],
          loc: loc
        )

        result = resolver.infer(param)
        expect(result.reason).to include("comments, title")
      end
    end

    context "with ConstantNode" do
      it "infers type from dependency" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
        const = TypeGuessr::Core::IR::ConstantNode.new(
          name: "DEFAULT_NAME",
          dependency: literal,
          loc: loc
        )

        result = resolver.infer(const)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("constant DEFAULT_NAME")
      end
    end

    context "with CallNode" do
      it "queries RBS for return type" do
        receiver_var = TypeGuessr::Core::IR::VariableNode.new(
          name: :str,
          kind: :local,
          dependency: TypeGuessr::Core::IR::LiteralNode.new(
            type: TypeGuessr::Core::Types::ClassInstance.new("String"),
            loc: loc
          ),
          called_methods: [],
          loc: loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :upcase,
          receiver: receiver_var,
          args: [],
          block_params: [],
          loc: loc
        )

        result = resolver.infer(call)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to eq("String#upcase")
      end

      it "handles Array method calls with element type substitution" do
        array_type = TypeGuessr::Core::Types::ArrayType.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer")
        )
        receiver_var = TypeGuessr::Core::IR::VariableNode.new(
          name: :arr,
          kind: :local,
          dependency: TypeGuessr::Core::IR::LiteralNode.new(
            type: array_type,
            loc: loc
          ),
          called_methods: [],
          loc: loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :compact,
          receiver: receiver_var,
          args: [],
          block_params: [],
          loc: loc
        )

        result = resolver.infer(call)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ArrayType)
        expect(result.type.element_type.name).to eq("Integer")
      end
    end

    context "with BlockParamSlot" do
      it "infers type from Array element type" do
        array_type = TypeGuessr::Core::Types::ArrayType.new(
          TypeGuessr::Core::Types::ClassInstance.new("String")
        )
        receiver_var = TypeGuessr::Core::IR::VariableNode.new(
          name: :arr,
          kind: :local,
          dependency: TypeGuessr::Core::IR::LiteralNode.new(
            type: array_type,
            loc: loc
          ),
          called_methods: [],
          loc: loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :each,
          receiver: receiver_var,
          args: [],
          block_params: [],
          loc: loc
        )
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(index: 0, call_node: call)

        result = resolver.infer(slot)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("Array[String]#each")
      end
    end

    context "with MergeNode" do
      it "creates union type from branches" do
        branch1 = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
        branch2 = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          loc: loc
        )
        merge = TypeGuessr::Core::IR::MergeNode.new(
          branches: [branch1, branch2],
          loc: loc
        )

        result = resolver.infer(merge)
        expect(result.type).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.type.types.map(&:name)).to contain_exactly("String", "Integer")
        expect(result.reason).to include("branch merge")
      end

      it "returns single type when only one branch" do
        branch = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
        merge = TypeGuessr::Core::IR::MergeNode.new(
          branches: [branch],
          loc: loc
        )

        result = resolver.infer(merge)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
      end
    end

    context "with DefNode" do
      it "infers return type from return node" do
        return_node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          loc: loc
        )
        def_node = TypeGuessr::Core::IR::DefNode.new(
          name: :foo,
          params: [],
          return_node: return_node,
          loc: loc
        )

        result = resolver.infer(def_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("def foo")
        expect(result.source).to eq(:project)
      end

      it "returns Unknown for method without body" do
        def_node = TypeGuessr::Core::IR::DefNode.new(
          name: :foo,
          params: [],
          return_node: nil,
          loc: loc
        )

        result = resolver.infer(def_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("method without body")
      end
    end

    context "caching" do
      it "caches inference results" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )

        result1 = resolver.infer(node)
        result2 = resolver.infer(node)

        expect(result1).to be(result2) # Same object reference
      end

      it "clears cache when requested" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )

        result1 = resolver.infer(node)
        resolver.clear_cache
        result2 = resolver.infer(node)

        expect(result1).to eq(result2) # Same value
        expect(result1).not_to be(result2) # Different object
      end
    end
  end
end
