# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"
require "ruby_lsp/type_guessr/runtime_adapter"
require "ruby_lsp/type_guessr/type_inferrer"

RSpec.describe RubyLsp::TypeGuessr::TypeInferrer do
  let(:global_state) do
    state = RubyLsp::GlobalState.new
    state.apply_options({})
    state
  end

  let(:runtime_adapter) { RubyLsp::TypeGuessr::RuntimeAdapter.new(global_state) }
  let(:type_inferrer) { described_class.new(global_state.index, runtime_adapter) }

  describe "#infer_receiver_type" do
    def parse_and_create_context(source)
      parsed = Prism.parse(source)
      # Find the CallNode in the AST
      call_node = find_node(parsed.value, Prism::CallNode)

      # Create a basic NodeContext (node, parent, nesting_nodes, call_node)
      RubyLsp::NodeContext.new(
        call_node,
        nil, # parent
        [],  # nesting_nodes
        nil  # call_node
      )
    end

    def find_node(node, type)
      return node if node.is_a?(type)

      if node.respond_to?(:child_nodes)
        node.child_nodes.compact.each do |child|
          result = find_node(child, type)
          return result if result
        end
      end

      nil
    end

    context "when receiver is a literal" do
      it "falls back to ruby-lsp for String literal" do
        source = '"hello".upcase'
        context = parse_and_create_context(source)

        result = type_inferrer.infer_receiver_type(context)

        expect(result).to be_a(RubyLsp::TypeInferrer::Type)
        expect(result.name).to eq("String")
      end

      it "falls back to ruby-lsp for Integer literal" do
        source = "42.to_s"
        context = parse_and_create_context(source)

        result = type_inferrer.infer_receiver_type(context)

        expect(result).to be_a(RubyLsp::TypeInferrer::Type)
        expect(result.name).to eq("Integer")
      end
    end

    context "when receiver is a variable" do
      it "infers type from indexed variable" do
        source = <<~RUBY
          name = "Alice"
          name.upcase
        RUBY

        # Index the source first
        runtime_adapter.index_source("file:///test.rb", source)

        # Parse and find the CallNode
        parsed = Prism.parse(source)
        call_nodes = []
        find_all_nodes(parsed.value, Prism::CallNode, call_nodes)
        call_node = call_nodes.last # The 'name.upcase' call

        # Create context with surrounding scope info
        node_context = RubyLsp::NodeContext.new(
          call_node,
          nil, # parent
          [],  # nesting_nodes
          nil  # call_node
        )

        result = type_inferrer.infer_receiver_type(node_context)

        # Should return GuessedType with String
        expect(result).to be_a(RubyLsp::TypeInferrer::GuessedType)
        expect(result.name).to eq("String")
      end
    end

    def find_all_nodes(node, type, results)
      results << node if node.is_a?(type)

      return unless node.respond_to?(:child_nodes)

      node.child_nodes.compact.each do |child|
        find_all_nodes(child, type, results)
      end
    end
  end

  describe "inheritance" do
    it "inherits from RubyLsp::TypeInferrer" do
      expect(described_class.superclass).to eq(RubyLsp::TypeInferrer)
    end
  end
end
