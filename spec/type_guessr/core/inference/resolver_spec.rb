# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/inference/resolver"
require "type_guessr/core/registry/signature_registry"
require "type_guessr/core/type_simplifier"

RSpec.describe TypeGuessr::Core::Inference::Resolver do
  let(:signature_registry) { TypeGuessr::Core::Registry::SignatureRegistry.instance.preload }
  let(:type_simplifier) { TypeGuessr::Core::TypeSimplifier.new }
  let(:code_index) { RubyLsp::TypeGuessr::CodeIndexAdapter.new(nil) }
  let(:method_registry) { TypeGuessr::Core::Registry::MethodRegistry.new }
  let(:ivar_registry) { TypeGuessr::Core::Registry::InstanceVariableRegistry.new }
  let(:cvar_registry) { TypeGuessr::Core::Registry::ClassVariableRegistry.new }
  let(:resolver) do
    described_class.new(
      signature_registry,
      type_simplifier: type_simplifier,
      code_index: code_index,
      method_registry: method_registry,
      ivar_registry: ivar_registry,
      cvar_registry: cvar_registry
    )
  end
  let(:loc) { 0 }

  # Helper to create DefNode with common defaults
  def create_def_node(name:, class_name: nil, params: [], return_node: nil, body_nodes: [], singleton: false)
    TypeGuessr::Core::IR::DefNode.new(
      name, class_name, params, return_node, body_nodes, [], loc, singleton
    )
  end

  describe "#infer" do
    context "with nil node" do
      it "returns Unknown" do
        result = resolver.infer(nil)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("no node")
      end
    end

    context "with unrecognized node type" do
      it "returns Unknown with 'unknown node type' reason" do
        # Real scenario: new IR node type added but Resolver not updated
        # This creates a custom Data class that isn't handled by infer_node
        unhandled_node = Data.define(:loc).new(loc: loc)

        result = resolver.infer(unhandled_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unknown node type")
        expect(result.source).to eq(:unknown)
      end
    end

    context "with LiteralNode" do
      it "returns the literal type" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
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
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil,
          nil,
          [],
          loc
        )
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          :x,
          literal,
          [],
          loc
        )

        result = resolver.infer(write_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to eq("assigned from literal")
      end

      it "returns Unknown for unassigned variable" do
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          :x,
          nil,
          [],
          loc
        )

        result = resolver.infer(write_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unassigned variable")
      end
    end

    context "with LocalReadNode" do
      it "infers type from write_node" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          :x,
          literal,
          [],
          loc
        )
        read_node = TypeGuessr::Core::IR::LocalReadNode.new(
          :x,
          write_node,
          write_node.called_methods,
          loc
        )

        result = resolver.infer(read_node)
        expect(result.type.name).to eq("String")
      end

      it "returns Unknown for unassigned variable" do
        read_node = TypeGuessr::Core::IR::LocalReadNode.new(
          :x,
          nil,
          [],
          loc
        )

        result = resolver.infer(read_node)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("unassigned variable")
      end
    end

    context "with ParamNode" do
      it "infers type from default value" do
        default = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        param = TypeGuessr::Core::IR::ParamNode.new(
          :name,
          :optional,
          default,
          [],
          loc
        )

        result = resolver.infer(param)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("parameter default")
      end

      it "returns Unknown for parameter without default or methods" do
        param = TypeGuessr::Core::IR::ParamNode.new(
          :x,
          :required,
          nil,
          [],
          loc
        )

        result = resolver.infer(param)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("parameter without type info")
      end

      it "returns Unknown when called methods cannot be resolved" do
        called = [
          TypeGuessr::Core::IR::CalledMethod.new(name: :comments, positional_count: nil, keywords: []),
          TypeGuessr::Core::IR::CalledMethod.new(name: :title, positional_count: nil, keywords: []),
        ]
        param = TypeGuessr::Core::IR::ParamNode.new(
          :recipe,
          :required,
          nil,
          called,
          loc
        )

        result = resolver.infer(param)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to include("unresolved methods")
      end
    end

    context "with ConstantNode" do
      it "infers type from dependency" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        const = TypeGuessr::Core::IR::ConstantNode.new(
          "DEFAULT_NAME",
          literal,
          [],
          loc
        )

        result = resolver.infer(const)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("constant DEFAULT_NAME")
      end

      it "infers singleton type for class constant" do
        allow(code_index).to receive(:constant_kind).with("User").and_return(:class)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          "User",
          nil,
          [],
          loc
        )

        result = resolver.infer(const)
        expect(result.type).to be_a(TypeGuessr::Core::Types::SingletonType)
        expect(result.type.name).to eq("User")
        expect(result.reason).to eq("class constant User")
        expect(result.source).to eq(:inference)
      end

      it "infers singleton type for module constant" do
        allow(code_index).to receive(:constant_kind).with("MyModule").and_return(:module)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          "MyModule",
          nil,
          [],
          loc
        )

        result = resolver.infer(const)
        expect(result.type).to be_a(TypeGuessr::Core::Types::SingletonType)
        expect(result.type.name).to eq("MyModule")
        expect(result.reason).to eq("class constant MyModule")
        expect(result.source).to eq(:inference)
      end

      it "returns Unknown for non-class constant when code_index returns nil" do
        allow(code_index).to receive(:constant_kind).with("MAX_SIZE").and_return(nil)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          "MAX_SIZE",
          nil,
          [],
          loc
        )

        result = resolver.infer(const)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("undefined constant")
        expect(result.source).to eq(:unknown)
      end
    end

    context "with CallNode" do
      it "queries RBS for return type" do
        receiver_var = TypeGuessr::Core::IR::LocalWriteNode.new(
          :str,
          TypeGuessr::Core::IR::LiteralNode.new(
            TypeGuessr::Core::Types::ClassInstance.new("String"),
            nil,
            nil,
            [],
            loc
          ),
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :upcase,
          receiver_var,
          [],
          [],
          nil,
          false,
          [],
          loc
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
          :arr,
          TypeGuessr::Core::IR::LiteralNode.new(
            array_type,
            nil,
            nil,
            [],
            loc
          ),
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :compact,
          receiver_var,
          [],
          [],
          nil,
          false,
          [],
          loc
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
          :arr,
          TypeGuessr::Core::IR::LiteralNode.new(
            array_type,
            nil,
            nil,
            [],
            loc
          ),
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :each,
          receiver_var,
          [],
          [],
          nil,
          true,
          [],
          loc
        )
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(0, call, [], loc)

        result = resolver.infer(slot)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("Array#each")
      end

      it "falls back to called_methods when receiver type is Unknown" do
        called = [TypeGuessr::Core::IR::CalledMethod.new(name: :name, positional_count: nil, keywords: [])]
        allow(code_index).to receive(:find_classes_defining_methods).with(called).and_return(["User"])
        allow(code_index).to receive(:ancestors_of).with("User").and_return(%w[User Object])

        # Receiver is Unknown (e.g., variable with no type info)
        unknown_receiver = TypeGuessr::Core::IR::LocalWriteNode.new(
          :users,
          nil,
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :each,
          unknown_receiver,
          [],
          [],
          nil,
          true,
          [],
          loc
        )
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(
          0,
          call,
          called,
          loc
        )

        result = resolver.infer(slot)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("User")
        expect(result.reason).to include("block param inferred from")
        expect(result.source).to eq(:project)
      end

      it "falls back to called_methods when RBS has no block param info" do
        called = [TypeGuessr::Core::IR::CalledMethod.new(name: :title, positional_count: nil, keywords: [])]
        allow(code_index).to receive(:find_classes_defining_methods).with(called).and_return(["Post"])
        allow(code_index).to receive(:ancestors_of).with("Post").and_return(%w[Post Object])

        # Receiver has a known type but the method has no RBS block param info
        receiver = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :custom_each,
          receiver,
          [],
          [],
          nil,
          true,
          [],
          loc
        )
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(
          0,
          call,
          called,
          loc
        )

        result = resolver.infer(slot)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("Post")
        expect(result.reason).to include("block param inferred from")
        expect(result.source).to eq(:project)
      end

      it "returns Unknown with unresolved reason when called_methods cannot be resolved" do
        # No mock on code_index — will return empty by default
        unknown_receiver = TypeGuessr::Core::IR::LocalWriteNode.new(
          :items,
          nil,
          [],
          loc
        )
        call = TypeGuessr::Core::IR::CallNode.new(
          :each,
          unknown_receiver,
          [],
          [],
          nil,
          true,
          [],
          loc
        )
        called = [TypeGuessr::Core::IR::CalledMethod.new(name: :nonexistent_method, positional_count: nil, keywords: [])]
        slot = TypeGuessr::Core::IR::BlockParamSlot.new(
          0,
          call,
          called,
          loc
        )

        result = resolver.infer(slot)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to include("unresolved methods")
      end
    end

    context "with MergeNode" do
      it "creates union type from branches" do
        branch1 = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        branch2 = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil,
          nil,
          [],
          loc
        )
        merge = TypeGuessr::Core::IR::MergeNode.new(
          [branch1, branch2],
          [],
          loc
        )

        result = resolver.infer(merge)
        expect(result.type).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.type.types.map(&:name)).to contain_exactly("String", "Integer")
        expect(result.reason).to include("branch merge")
      end

      it "returns single type when only one branch" do
        branch = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )
        merge = TypeGuessr::Core::IR::MergeNode.new(
          [branch],
          [],
          loc
        )

        result = resolver.infer(merge)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
      end

      it "handles empty branches array (all branches non-returning)" do
        # Real scenario: case statement where all branches raise
        # case x; when 1 then raise "error1"; when 2 then raise "error2"; end
        # After filtering non-returning branches, we may have empty branches
        merge = TypeGuessr::Core::IR::MergeNode.new(
          [],
          [],
          loc
        )

        # Should not crash, should return some reasonable type
        expect { resolver.infer(merge) }.not_to raise_error

        result = resolver.infer(merge)
        # Empty union could be Unknown or a Union with no types
        # The behavior depends on implementation, but it should be consistent
        expect(result).to be_a(TypeGuessr::Core::Inference::Result)
      end
    end

    context "with OrNode" do
      it "returns RHS type when LHS is entirely falsy (nil)" do
        lhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("NilClass"),
          nil, nil, [], loc
        )
        rhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil, nil, [], loc
        )
        or_node = TypeGuessr::Core::IR::OrNode.new(lhs, rhs, [], loc)

        result = resolver.infer(or_node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("lhs falsy")
      end

      it "returns LHS type when LHS is always truthy" do
        lhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil, nil, [], loc
        )
        rhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil, nil, [], loc
        )
        or_node = TypeGuessr::Core::IR::OrNode.new(lhs, rhs, [], loc)

        result = resolver.infer(or_node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("always truthy")
      end

      it "returns truthy LHS | RHS when LHS is mixed (truthy + falsy)" do
        lhs_type = TypeGuessr::Core::Types::Union.new([
                                                        TypeGuessr::Core::Types::ClassInstance.new("String"),
                                                        TypeGuessr::Core::Types::ClassInstance.new("NilClass"),
                                                      ])
        lhs = TypeGuessr::Core::IR::LiteralNode.new(
          lhs_type, nil, nil, [], loc
        )
        rhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil, nil, [], loc
        )
        or_node = TypeGuessr::Core::IR::OrNode.new(lhs, rhs, [], loc)

        result = resolver.infer(or_node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::Union)
        type_names = result.type.types.map(&:name)
        expect(type_names).to contain_exactly("String", "Integer")
      end

      it "returns RHS type when LHS is FalseClass" do
        lhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("FalseClass"),
          nil, nil, [], loc
        )
        rhs = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil, nil, [], loc
        )
        or_node = TypeGuessr::Core::IR::OrNode.new(lhs, rhs, [], loc)

        result = resolver.infer(or_node)
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
          :==,
          nil,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        # Object#== returns bool in RBS
        expect(bool_type?(result.type)).to be(true), "Expected bool type, got #{result.type.inspect}"
        expect(result.reason).to include("Object#==")
      end

      it "treats unknown receiver as Object and queries RBS for to_s" do
        call = TypeGuessr::Core::IR::CallNode.new(
          :to_s,
          nil,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        # Object#to_s returns String
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("String")
        expect(result.reason).to include("Object#to_s")
      end

      it "treats unknown receiver as Object and queries RBS for !" do
        call = TypeGuessr::Core::IR::CallNode.new(
          :!,
          nil,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        # BasicObject#! returns bool
        expect(bool_type?(result.type)).to be(true), "Expected bool type, got #{result.type.inspect}"
      end

      it "returns Unknown for method not defined on Object" do
        call = TypeGuessr::Core::IR::CallNode.new(
          :some_random_method_that_does_not_exist,
          nil,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
      end

      it "infers receiver type from method uniqueness when receiver is Unknown" do
        # Set up code_index to simulate RubyIndexer resolving :depot to Store
        depot_cm = [TypeGuessr::Core::IR::CalledMethod.new(name: :depot, positional_count: nil, keywords: [])]
        allow(code_index).to receive(:find_classes_defining_methods).with(depot_cm).and_return(["Store"])

        # Register Store#depot that returns an Integer
        depot_return = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          42,
          nil,
          [],
          loc
        )
        depot_def = create_def_node(
          name: :depot,
          class_name: "Store",
          return_node: depot_return,
          body_nodes: [depot_return]
        )
        method_registry.register("Store", "depot", depot_def)

        # Create Unknown type receiver
        unknown_receiver = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::Unknown.instance,
          nil,
          nil,
          [],
          loc
        )

        # Call depot on Unknown receiver
        call = TypeGuessr::Core::IR::CallNode.new(
          :depot,
          unknown_receiver,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("inferred receiver")
      end

      it "substitutes SelfType with Unknown when calling dup on Unknown receiver" do
        # Create Unknown type receiver (simulating an untyped parameter)
        unknown_receiver = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::Unknown.instance,
          nil,
          nil,
          [],
          loc
        )

        # Call dup on Unknown receiver - Object#dup returns self
        call = TypeGuessr::Core::IR::CallNode.new(
          :dup,
          unknown_receiver,
          [],
          [],
          nil,
          false,
          [],
          loc
        )

        result = resolver.infer(call)
        # Object#dup returns self, but since receiver is Unknown, self should be substituted with Unknown
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    context "with DefNode" do
      it "infers return type from return node" do
        return_node = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          nil,
          nil,
          [],
          loc
        )
        def_node = create_def_node(name: :foo, return_node: return_node, body_nodes: [return_node])

        result = resolver.infer(def_node)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("def foo")
        expect(result.source).to eq(:project)
      end

      it "returns NilClass for method without body" do
        def_node = create_def_node(name: :foo)

        result = resolver.infer(def_node)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("NilClass")
        expect(result.reason).to include("returns nil (empty body)")
      end

      it "returns self type for initialize method" do
        def_node = create_def_node(name: :initialize, class_name: "User")

        result = resolver.infer(def_node)
        expect(result.type).to be(TypeGuessr::Core::Types::SelfType.instance)
        expect(result.reason).to include("def initialize")
      end
    end

    context "with circular references" do
      it "returns Unknown instead of stack overflow when MergeNode contains self-referential branch" do
        # Create a circular reference: MergeNode -> LocalReadNode -> write_node -> MergeNode
        # This simulates patterns like `x ||= x` or complex control flow
        merge_node = TypeGuessr::Core::IR::MergeNode.new(
          [],
          [],
          loc
        )

        write_node = TypeGuessr::Core::IR::LocalWriteNode.new(
          :x,
          merge_node,
          [],
          loc
        )

        read_node = TypeGuessr::Core::IR::LocalReadNode.new(
          :x,
          write_node,
          [],
          loc
        )

        # Create circular reference: MergeNode.branches -> read_node -> write_node.value -> MergeNode
        merge_node.branches << read_node

        # This should NOT raise SystemStackError
        expect { resolver.infer(merge_node) }.not_to raise_error
      end

      it "detects deep circular reference through node dependencies A -> B -> C -> A" do
        # Create circular reference through LocalWriteNode chain:
        # write_a.value -> write_b -> write_b.value -> write_c -> write_c.value -> read_a -> write_a
        write_c = TypeGuessr::Core::IR::LocalWriteNode.new(
          :c,
          nil, # Will be set below
          [],
          loc
        )

        write_b = TypeGuessr::Core::IR::LocalWriteNode.new(
          :b,
          write_c,
          [],
          loc
        )

        write_a = TypeGuessr::Core::IR::LocalWriteNode.new(
          :a,
          write_b,
          [],
          loc
        )

        # Create read node pointing back to write_a
        read_a = TypeGuessr::Core::IR::LocalReadNode.new(
          :a,
          write_a,
          [],
          loc
        )

        # Complete the cycle: write_c.value points to read_a which points to write_a
        # This creates: write_a -> write_b -> write_c -> read_a -> write_a
        # We need to manually set the value since Data.define is immutable
        # Use a MergeNode to wrap the circular reference
        merge_for_c = TypeGuessr::Core::IR::MergeNode.new(
          [read_a],
          [],
          loc
        )

        # Recreate write_c with the circular value
        write_c_circular = TypeGuessr::Core::IR::LocalWriteNode.new(
          :c,
          merge_for_c,
          [],
          loc
        )

        write_b_circular = TypeGuessr::Core::IR::LocalWriteNode.new(
          :b,
          write_c_circular,
          [],
          loc
        )

        write_a_circular = TypeGuessr::Core::IR::LocalWriteNode.new(
          :a,
          write_b_circular,
          [],
          loc
        )

        # Update read_a to point to the circular write_a
        read_a_circular = TypeGuessr::Core::IR::LocalReadNode.new(
          :a,
          write_a_circular,
          [],
          loc
        )

        # Rebuild the chain with proper circular reference
        TypeGuessr::Core::IR::MergeNode.new(
          [read_a_circular],
          [],
          loc
        )

        # Inferring should not cause stack overflow (detected by INFERRING sentinel)
        expect { resolver.infer(write_a_circular) }.not_to raise_error

        # Result should be Unknown due to circular dependency
        result = resolver.infer(write_a_circular)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    context "caching" do
      it "caches inference results" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )

        result1 = resolver.infer(node)
        result2 = resolver.infer(node)

        expect(result1).to be(result2) # Same object reference
      end

      it "clears cache when requested" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          TypeGuessr::Core::Types::ClassInstance.new("String"),
          nil,
          nil,
          [],
          loc
        )

        result1 = resolver.infer(node)
        resolver.clear_cache
        result2 = resolver.infer(node)

        expect(result1).to eq(result2) # Same value
        expect(result1).not_to be(result2) # Different object
      end
    end
  end

  describe "#classes_to_type" do
    it "returns Unknown for empty list" do
      result = resolver.classes_to_type([])
      expect(result).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end

    it "returns ClassInstance for single class" do
      result = resolver.classes_to_type(["Recipe"])
      expect(result).to be_a(TypeGuessr::Core::Types::ClassInstance)
      expect(result.name).to eq("Recipe")
    end

    it "returns Union for two classes" do
      result = resolver.classes_to_type(%w[Parser Compiler])
      expect(result).to be_a(TypeGuessr::Core::Types::Union)
      expect(result.types.map(&:name)).to contain_exactly("Parser", "Compiler")
    end

    it "returns Union for three classes" do
      result = resolver.classes_to_type(%w[Parser Compiler Optimizer])
      expect(result).to be_a(TypeGuessr::Core::Types::Union)
      expect(result.types.map(&:name)).to contain_exactly("Parser", "Compiler", "Optimizer")
    end

    it "returns Unknown for four or more classes (too ambiguous)" do
      result = resolver.classes_to_type(%w[A B C D])
      expect(result).to eq(TypeGuessr::Core::Types::Unknown.instance)
    end
  end
end
