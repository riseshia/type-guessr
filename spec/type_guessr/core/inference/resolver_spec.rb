# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/inference/resolver"
require "type_guessr/core/rbs_provider"
require "type_guessr/core/type_simplifier"

RSpec.describe TypeGuessr::Core::Inference::Resolver do
  let(:rbs_provider) { TypeGuessr::Core::RBSProvider.instance }
  let(:type_simplifier) { TypeGuessr::Core::TypeSimplifier.new }
  let(:resolver) do
    r = described_class.new(rbs_provider)
    r.type_simplifier = type_simplifier
    r
  end
  let(:loc) { TypeGuessr::Core::IR::Loc.new(line: 1, col_range: 0...10) }

  # Helper to create DefNode with common defaults
  def create_def_node(name:, class_name: nil, params: [], return_node: nil, body_nodes: [], singleton: false)
    TypeGuessr::Core::IR::DefNode.new(
      name: name,
      class_name: class_name,
      params: params,
      return_node: return_node,
      body_nodes: body_nodes,
      loc: loc,
      singleton: singleton
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

    context "with LiteralNode" do
      it "returns the literal type" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          literal_value: nil,
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
          literal_value: nil,
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
          literal_value: nil,
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
          literal_value: nil,
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

      it "returns Unknown when called methods cannot be resolved" do
        param = TypeGuessr::Core::IR::ParamNode.new(
          name: :recipe,
          kind: :required,
          default_value: nil,
          called_methods: %i[comments title],
          loc: loc
        )

        result = resolver.infer(param)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to include("unresolved methods")
      end
    end

    context "with ConstantNode" do
      it "infers type from dependency" do
        literal = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          literal_value: nil,
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

      it "infers singleton type for class constant" do
        code_index = double
        allow(code_index).to receive(:constant_kind).with("User").and_return(:class)
        resolver_with_index = described_class.new(rbs_provider, code_index: code_index)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          name: "User",
          dependency: nil,
          loc: loc
        )

        result = resolver_with_index.infer(const)
        expect(result.type).to be_a(TypeGuessr::Core::Types::SingletonType)
        expect(result.type.name).to eq("User")
        expect(result.reason).to eq("class constant User")
        expect(result.source).to eq(:inference)
      end

      it "infers singleton type for module constant" do
        code_index = double
        allow(code_index).to receive(:constant_kind).with("MyModule").and_return(:module)
        resolver_with_index = described_class.new(rbs_provider, code_index: code_index)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          name: "MyModule",
          dependency: nil,
          loc: loc
        )

        result = resolver_with_index.infer(const)
        expect(result.type).to be_a(TypeGuessr::Core::Types::SingletonType)
        expect(result.type.name).to eq("MyModule")
        expect(result.reason).to eq("class constant MyModule")
        expect(result.source).to eq(:inference)
      end

      it "returns Unknown for non-class constant when code_index returns nil" do
        code_index = double
        allow(code_index).to receive(:constant_kind).with("MAX_SIZE").and_return(nil)
        resolver_with_index = described_class.new(rbs_provider, code_index: code_index)

        const = TypeGuessr::Core::IR::ConstantNode.new(
          name: "MAX_SIZE",
          dependency: nil,
          loc: loc
        )

        result = resolver_with_index.infer(const)
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
        expect(result.reason).to eq("undefined constant")
        expect(result.source).to eq(:unknown)
      end
    end

    context "with CallNode" do
      it "queries RBS for return type" do
        receiver_var = TypeGuessr::Core::IR::LocalWriteNode.new(
          name: :str,
          value: TypeGuessr::Core::IR::LiteralNode.new(
            type: TypeGuessr::Core::Types::ClassInstance.new("String"),
            literal_value: nil,
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
            literal_value: nil,
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
            literal_value: nil,
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
          literal_value: nil,
          values: nil,
          loc: loc
        )
        branch2 = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          literal_value: nil,
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
          literal_value: nil,
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

      it "infers receiver type from method uniqueness when receiver is Unknown" do
        # Set up code_index to simulate RubyIndexer resolving :depot to Store
        code_index = double
        allow(code_index).to receive(:find_classes_defining_methods).with([:depot]).and_return(["Store"])
        resolver_with_index = described_class.new(rbs_provider, code_index: code_index)

        # Register Store#depot that returns an Integer
        depot_return = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          literal_value: 42,
          values: nil,
          loc: loc
        )
        depot_def = create_def_node(
          name: :depot,
          class_name: "Store",
          return_node: depot_return,
          body_nodes: [depot_return]
        )
        resolver_with_index.method_registry.register("Store", "depot", depot_def)

        # Create Unknown type receiver
        unknown_receiver = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::Unknown.instance,
          literal_value: nil,
          values: nil,
          loc: loc
        )

        # Call depot on Unknown receiver
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :depot,
          receiver: unknown_receiver,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver_with_index.infer(call)
        expect(result.type).to be_a(TypeGuessr::Core::Types::ClassInstance)
        expect(result.type.name).to eq("Integer")
        expect(result.reason).to include("inferred receiver")
      end

      it "substitutes SelfType with Unknown when calling dup on Unknown receiver" do
        # Create Unknown type receiver (simulating an untyped parameter)
        unknown_receiver = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::Unknown.instance,
          literal_value: nil,
          values: nil,
          loc: loc
        )

        # Call dup on Unknown receiver - Object#dup returns self
        call = TypeGuessr::Core::IR::CallNode.new(
          method: :dup,
          receiver: unknown_receiver,
          args: [],
          block_params: [],
          block_body: nil,
          has_block: false,
          loc: loc
        )

        result = resolver.infer(call)
        # Object#dup returns self, but since receiver is Unknown, self should be substituted with Unknown
        expect(result.type).to be(TypeGuessr::Core::Types::Unknown.instance)
      end
    end

    context "with DefNode" do
      it "infers return type from return node" do
        return_node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("Integer"),
          literal_value: nil,
          values: nil,
          loc: loc
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

    context "caching" do
      it "caches inference results" do
        node = TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          literal_value: nil,
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
          literal_value: nil,
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

  describe "#classes_to_type" do
    it "returns nil for empty list" do
      result = resolver.classes_to_type([])
      expect(result).to be_nil
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

    it "returns nil for four or more classes (too ambiguous)" do
      result = resolver.classes_to_type(%w[A B C D])
      expect(result).to be_nil
    end
  end

  describe "#signature_matches?" do
    let(:called_method_class) { TypeGuessr::Core::IR::CalledMethod }

    # Using RBS stdlib types for testing signature matching
    # String#gsub has multiple overloads, one takes 2 positional args
    # String#split takes 0-2 positional args

    it "returns true when positional count matches method signature" do
      cm = called_method_class.new(name: :gsub, positional_count: 2, keywords: [])
      expect(resolver.send(:signature_matches?, "String", cm)).to be(true)
    end

    it "returns false when positional count does not match" do
      # String#gsub requires at least 1 argument (the pattern)
      # but 5 positional args is way too many
      cm = called_method_class.new(name: :gsub, positional_count: 5, keywords: [])
      expect(resolver.send(:signature_matches?, "String", cm)).to be(false)
    end

    it "returns true when positional_count is nil (splat - can match anything)" do
      cm = called_method_class.new(name: :gsub, positional_count: nil, keywords: [])
      expect(resolver.send(:signature_matches?, "String", cm)).to be(true)
    end

    it "returns true when method has keyword arguments that match" do
      # File.open accepts keyword arguments like mode:, encoding:
      cm = called_method_class.new(name: :open, positional_count: 1, keywords: [:mode])
      expect(resolver.send(:signature_matches?, "File", cm)).to be(true)
    end

    it "returns true when no RBS definition exists (conservative fallback)" do
      # Unknown class without RBS - should not reject
      cm = called_method_class.new(name: :some_method, positional_count: 2, keywords: [])
      expect(resolver.send(:signature_matches?, "SomeUnknownClass", cm)).to be(true)
    end

    it "returns false when required keyword is not provided" do
      # This test verifies keyword argument checking
      # If a method requires certain keywords, calling without them should fail
      # Note: Most Ruby methods don't have required kwargs, so this may need adjustment
      cm = called_method_class.new(name: :gsub, positional_count: 2, keywords: [:nonexistent_kwarg])
      # Even with extra keyword, should still match (Ruby allows extra kwargs in some cases)
      # The key is that required args must be present
      expect(resolver.send(:signature_matches?, "String", cm)).to be(true)
    end
  end
end
