# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/type_guessr/graph_builder"

RSpec.describe RubyLsp::TypeGuessr::GraphBuilder do
  let(:loc) { TypeGuessr::Core::IR::Loc.new(line: 10, col_range: 0...10) }
  let(:nodes) { {} }

  # Create a minimal mock runtime adapter
  let(:runtime_adapter) do
    node_store = nodes
    adapter = instance_double(RubyLsp::TypeGuessr::RuntimeAdapter)
    allow(adapter).to receive(:find_node_by_key) { |key| node_store[key] }
    allow(adapter).to receive(:infer_type) do |_node|
      TypeGuessr::Core::Inference::Result.new(
        TypeGuessr::Core::Types::ClassInstance.new("String"),
        "test",
        :test
      )
    end
    adapter
  end

  let(:graph_builder) { described_class.new(runtime_adapter) }

  describe "#build" do
    context "when node is not found" do
      it "returns nil" do
        result = graph_builder.build("nonexistent:key")
        expect(result).to be_nil
      end
    end

    context "with a simple literal node" do
      let(:literal) do
        TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
      end

      before do
        nodes["Test:lit:ClassInstance:10"] = literal
      end

      it "returns graph with single node" do
        result = graph_builder.build("Test:lit:ClassInstance:10")

        expect(result).to be_a(Hash)
        expect(result[:nodes].size).to eq(1)
        expect(result[:edges]).to eq([])
        expect(result[:root_key]).to eq("Test:lit:ClassInstance:10")
      end

      it "serializes node correctly" do
        result = graph_builder.build("Test:lit:ClassInstance:10")
        node = result[:nodes].first

        expect(node[:key]).to eq("Test:lit:ClassInstance:10")
        expect(node[:type]).to eq("LiteralNode")
        expect(node[:line]).to eq(10)
        expect(node[:inferred_type]).to eq("String")
        expect(node[:details]).to have_key(:literal_type)
      end
    end

    context "with a variable node with dependency" do
      let(:literal) do
        TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
      end

      let(:variable) do
        TypeGuessr::Core::IR::VariableNode.new(
          name: :name,
          kind: :local,
          dependency: literal,
          called_methods: [],
          loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 0...10)
        )
      end

      before do
        nodes["Test:var:name:5"] = variable
        nodes["Test:lit:ClassInstance:10"] = literal
      end

      it "traverses dependencies and creates edges" do
        result = graph_builder.build("Test:var:name:5")

        expect(result[:nodes].size).to eq(2)
        expect(result[:edges].size).to eq(1)
        expect(result[:edges].first[:from]).to eq("Test:var:name:5")
        expect(result[:edges].first[:to]).to eq("Test:lit:ClassInstance:10")
      end
    end

    context "with diamond pattern (same dependency from multiple nodes)" do
      let(:literal) do
        TypeGuessr::Core::IR::LiteralNode.new(
          type: TypeGuessr::Core::Types::ClassInstance.new("String"),
          loc: loc
        )
      end

      let(:branch_a) do
        TypeGuessr::Core::IR::VariableNode.new(
          name: :a,
          kind: :local,
          dependency: literal,
          called_methods: [],
          loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 0...10)
        )
      end

      let(:branch_b) do
        TypeGuessr::Core::IR::VariableNode.new(
          name: :b,
          kind: :local,
          dependency: literal,
          called_methods: [],
          loc: TypeGuessr::Core::IR::Loc.new(line: 6, col_range: 0...10)
        )
      end

      let(:merge) do
        TypeGuessr::Core::IR::MergeNode.new(
          branches: [branch_a, branch_b],
          loc: TypeGuessr::Core::IR::Loc.new(line: 7, col_range: 0...10)
        )
      end

      before do
        nodes["Test:merge:7"] = merge
        nodes["Test:var:a:5"] = branch_a
        nodes["Test:var:b:6"] = branch_b
        nodes["Test:lit:ClassInstance:10"] = literal
      end

      it "includes shared node only once" do
        result = graph_builder.build("Test:merge:7")

        # merge -> var1, merge -> var2, var1 -> literal, var2 -> literal
        # but literal should only appear once in nodes
        literal_nodes = result[:nodes].select { |n| n[:type] == "LiteralNode" }
        expect(literal_nodes.size).to eq(1)
      end
    end
  end

  describe "node type formatting" do
    it "formats ArrayType correctly" do
      allow(runtime_adapter).to receive(:infer_type).and_return(
        TypeGuessr::Core::Inference::Result.new(
          TypeGuessr::Core::Types::ArrayType.new(
            TypeGuessr::Core::Types::ClassInstance.new("Integer")
          ),
          "test",
          :test
        )
      )

      literal = TypeGuessr::Core::IR::LiteralNode.new(
        type: TypeGuessr::Core::Types::ArrayType.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer")
        ),
        loc: loc
      )
      nodes["Test:lit:ArrayType:10"] = literal

      result = graph_builder.build("Test:lit:ArrayType:10")
      expect(result[:nodes].first[:inferred_type]).to eq("Array[Integer]")
    end

    it "formats Union correctly" do
      allow(runtime_adapter).to receive(:infer_type).and_return(
        TypeGuessr::Core::Inference::Result.new(
          TypeGuessr::Core::Types::Union.new([
                                               TypeGuessr::Core::Types::ClassInstance.new("String"),
                                               TypeGuessr::Core::Types::ClassInstance.new("Integer"),
                                             ]),
          "test",
          :test
        )
      )

      literal = TypeGuessr::Core::IR::LiteralNode.new(
        type: TypeGuessr::Core::Types::ClassInstance.new("String"),
        loc: loc
      )
      nodes["Test:lit:ClassInstance:10"] = literal

      result = graph_builder.build("Test:lit:ClassInstance:10")
      expect(result[:nodes].first[:inferred_type]).to eq("String | Integer")
    end

    it "formats DuckType correctly" do
      allow(runtime_adapter).to receive(:infer_type).and_return(
        TypeGuessr::Core::Inference::Result.new(
          TypeGuessr::Core::Types::DuckType.new(%i[foo bar]),
          "test",
          :test
        )
      )

      param = TypeGuessr::Core::IR::ParamNode.new(
        name: :x,
        kind: :required,
        default_value: nil,
        called_methods: %i[foo bar],
        loc: loc
      )
      nodes["Test:param:x:10"] = param

      result = graph_builder.build("Test:param:x:10")
      inferred_type = result[:nodes].first[:inferred_type]
      expect(inferred_type).to match(/responds to #(foo|bar), #(foo|bar)/)
    end
  end

  describe "node details extraction" do
    it "extracts DefNode details" do
      def_node = TypeGuessr::Core::IR::DefNode.new(
        name: :save,
        params: [
          TypeGuessr::Core::IR::ParamNode.new(
            name: :user, kind: :required, default_value: nil, called_methods: [], loc: loc
          ),
        ],
        return_node: nil,
        body_nodes: [],
        loc: loc
      )
      nodes["Test:def:save:10"] = def_node

      result = graph_builder.build("Test:def:save:10")
      details = result[:nodes].first[:details]

      expect(details[:name]).to eq("save")
      expect(details[:param_signatures]).to eq(["user: String"])
    end

    it "extracts CallNode details" do
      call_node = TypeGuessr::Core::IR::CallNode.new(
        method: :upcase,
        receiver: nil,
        args: [],
        block_params: [],
        block_body: nil,
        has_block: true,
        loc: loc
      )
      nodes["Test:call:upcase:10"] = call_node

      result = graph_builder.build("Test:call:upcase:10")
      details = result[:nodes].first[:details]

      expect(details[:method]).to eq("upcase")
      expect(details[:has_block]).to be true
    end

    it "extracts VariableNode details for write" do
      var_node = TypeGuessr::Core::IR::VariableNode.new(
        name: :user,
        kind: :instance,
        dependency: nil,
        called_methods: %i[name email],
        loc: loc
      )
      nodes["Test:var:user:10"] = var_node

      result = graph_builder.build("Test:var:user:10")
      details = result[:nodes].first[:details]

      expect(details[:name]).to eq("user")
      expect(details[:kind]).to eq("instance")
      expect(details[:called_methods]).to eq(%w[name email])
      expect(details[:is_read]).to be false
    end

    it "extracts VariableNode details for read" do
      write_node = TypeGuessr::Core::IR::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: nil,
        called_methods: [],
        loc: TypeGuessr::Core::IR::Loc.new(line: 5, col_range: 0...10)
      )
      read_node = TypeGuessr::Core::IR::VariableNode.new(
        name: :user,
        kind: :local,
        dependency: write_node,
        called_methods: [],
        loc: loc
      )
      nodes["Test:var:user:10"] = read_node
      nodes["Test:var:user:5"] = write_node

      result = graph_builder.build("Test:var:user:10")
      read_details = result[:nodes].find { |n| n[:line] == 10 }[:details]
      write_details = result[:nodes].find { |n| n[:line] == 5 }[:details]

      expect(read_details[:is_read]).to be true
      expect(write_details[:is_read]).to be false
    end
  end
end
