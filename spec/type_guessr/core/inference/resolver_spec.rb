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
          values: nil,
          loc: loc
        )

        result = resolver.infer(node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to eq("literal")
        expect(result.source).to eq(:literal)
      end
    end

    context "with LocalWriteNode" do
      it "infers type from value" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          values: nil,
          loc: loc
        )
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :x,
          value: literal,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(write_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to eq("assigned from literal")
      end

      it "returns Unknown for unassigned variable" do
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :x,
          value: nil,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(write_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unassigned variable")
      end
    end

    context "with LocalReadNode" do
      it "infers type from write_node" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
          loc: loc
        )
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :x,
          value: literal,
          called_methods: [],
          loc: loc
        )
        read_node = TypeGuessr::Core::IR::LocalReadNode.new(
          name: :x,
          write_node: write_node,
          called_methods: write_node.called_methods,
          loc: loc
        )

        result = resolver.infer(read_node)
        expect(result.type.name).to eq("String")
      end

      it "returns Unknown for unassigned variable" do
        read_node = TypeGuessr::Core::IR::LocalReadNode.new(
          name: :x,
          write_node: nil,
          called_methods: [],
          loc: loc
        )

        result = resolver.infer(read_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unassigned variable")
      end
    end

    context "with ParamNode" do
      it "infers type from default value" do
        default = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
          loc: loc
        )
        param = TypeGuessr::Core::IR::ParamNode.new(
          name: :name,
          kind: :optional,
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
          kind: :required,
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
          kind: :required,
          default_value: nil,
          called_methods: %i[comments title],
          loc: loc
        )

        result = resolver.infer(param)
        expect(result.type).to be_a(TypeGuessr::Core::Types::DuckType)
        expect(result.type.methods).to eq(%i[comments title])
      end
    end

    context "with ConstantNode" do
      it "infers type from dependency" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
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
        receiver_var = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :str,
          value: TypeGuessr::Core::IR::LiteralNode.new(
            type: TypeGuessr::Core::Types::ClassInstance.new("String"),
            values: nil,
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
          block_body: nil,
          has_block: false,
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
        receiver_var = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :arr,
          value: TypeGuessr::Core::IR::LiteralNode.new(
            type: array_type,
            values: nil,
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
          block_body: nil,
          has_block: false,
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
        receiver_var = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :arr,
          value: TypeGuessr::Core::IR::LiteralNode.new(
            type: array_type,
            values: nil,
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
          block_body: nil,
          has_block: true,
          loc: loc
        )
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(index: 0, call_node: call, loc: loc)

        result = resolver.infer(slot)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("Array#each")
      end
    end

    context "with MergeNode" do
      it "creates union type from branches" do
        branch1 = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
          loc: loc
        )
        branch2 = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          values: nil,
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
          values: nil,
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

    context "with unknown receiver fallback to Object" do
      # Helper to check if type is bool (either Union[TrueClass, FalseClass] or ClassInstance("bool"))
      def bool_type?(type)
        case type
        when TypeGuessr::Core::Types::Union
          type.types.map(&:name).sort == %w[FalseClass TrueClass]
        when TypeGuessr::Core::Types::ClassInstance
          type.name == "bool"
        else
          false
        end
      end

      it "treats unknown receiver as Object and queries RBS for ==" do
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :==,
          receiver: nil,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver.infer(call)
        # Object#== returns bool in RBS
        expect(bool_type?(result.type)).to be(true), "Expected bool type, got #{result.type.inspect}"
        expect(result.reason).to include("Object#==")
      end

      it "treats unknown receiver as Object and queries RBS for to_s" do
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :to_s,
          receiver: nil,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver.infer(call)
        # Object#to_s returns String
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("Object#to_s")
      end

      it "treats unknown receiver as Object and queries RBS for !" do
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :!,
          receiver: nil,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver.infer(call)
        # BasicObject#! returns bool
        expect(bool_type?(result.type)).to be(true), "Expected bool type, got #{result.type.inspect}"
      end

      it "returns Unknown for method not defined on Object" do
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :some_random_method_that_does_not_exist,
          receiver: nil,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver.infer(call)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    context "with DefNode" do
      it "infers return type from return node" do
        return_node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          values: nil,
          loc: loc
        )
        def_node = TypeGuessr::Core::IR::DefNode.new(
          name: :foo,
          params: [],
          return_node: return_node,
          body_nodes: [return_node],
          loc: loc
        )

        result = resolver.infer(def_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("def foo")
        expect(result.source).to eq(:project)
      end

      it "returns NilClass for method without body" do
        def_node = TypeGuessr::Core::IR::DefNode.new(
          name: :foo,
          params: [],
          return_node: nil,
          body_nodes: [],
          loc: loc
        )

        result = resolver.infer(def_node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("NilClass")
        expect(result.reason).to include("returns nil (empty body)")
      end
    end

    context "caching" do
      it "caches inference results" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
          loc: loc
        )

        result1 = resolver.infer(node)
        result2 = resolver.infer(node)

        expect(result1).to be(result2) # Same object reference
      end

      it "clears cache when requested" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          values: nil,
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

  describe "#registered_classes" do
    it "returns empty array when no methods registered" do
      expect(resolver.registered_classes).to eq([])
    end

    it "returns list of registered class names" do
      def_node1 = TypeGuessr::Core::IR::DefNode.new(
        name: :save, params: [], return_node: nil, body_nodes: [], loc: loc
      )
      def_node2 = TypeGuessr::Core::IR::DefNode.new(
        name: :delete, params: [], return_node: nil, body_nodes: [], loc: loc
      )

      resolver.register_method("User", "save", def_node1)
      resolver.register_method("Post", "delete", def_node2)

      expect(resolver.registered_classes).to contain_exactly("User", "Post")
    end

    it "returns frozen array" do
      expect(resolver.registered_classes).to be_frozen
    end
  end

  describe "#methods_for_class" do
    it "returns empty hash for unknown class" do
      expect(resolver.methods_for_class("Unknown")).to eq({})
    end

    it "returns methods hash for registered class" do
      def_node = TypeGuessr::Core::IR::DefNode.new(
        name: :save, params: [], return_node: nil, body_nodes: [], loc: loc
      )
      resolver.register_method("User", "save", def_node)

      methods = resolver.methods_for_class("User")
      expect(methods.keys).to eq(["save"])
      expect(methods["save"]).to eq(def_node)
    end

    it "returns frozen hash" do
      expect(resolver.methods_for_class("User")).to be_frozen
    end
  end

  describe "#search_methods" do
    before do
      user_save = TypeGuessr::Core::IR::DefNode.new(
        name: :save, params: [], return_node: nil, body_nodes: [], loc: loc
      )
      user_delete = TypeGuessr::Core::IR::DefNode.new(
        name: :delete, params: [], return_node: nil, body_nodes: [], loc: loc
      )
      post_save = TypeGuessr::Core::IR::DefNode.new(
        name: :save, params: [], return_node: nil, body_nodes: [], loc: loc
      )

      resolver.register_method("User", "save", user_save)
      resolver.register_method("User", "delete", user_delete)
      resolver.register_method("Post", "save", post_save)
    end

    it "finds methods by method name" do
      results = resolver.search_methods("save")
      expect(results.size).to eq(2)
      expect(results.map { |r| r[0..1] }).to contain_exactly(
        %w[User save],
        %w[Post save]
      )
    end

    it "finds methods by class name" do
      results = resolver.search_methods("User")
      expect(results.size).to eq(2)
      expect(results.map { |r| r[1] }).to contain_exactly("save", "delete")
    end

    it "finds methods by full name" do
      results = resolver.search_methods("User#save")
      expect(results.size).to eq(1)
      expect(results[0][0..1]).to eq(%w[User save])
    end

    it "returns empty array for no match" do
      results = resolver.search_methods("Unknown")
      expect(results).to eq([])
    end
  end
end
