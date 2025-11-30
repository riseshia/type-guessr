# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

RSpec.describe RubyLsp::TypeGuessr::TypeInferrer do
  subject(:inferrer) { described_class.new(index) }

  let(:index) { RubyIndexer::Index.new }

  describe "inheritance" do
    it "inherits from RubyLsp::TypeInferrer" do
      expect(inferrer).to be_a(RubyLsp::TypeInferrer)
    end
  end

  describe "#infer_receiver_type" do
    it "responds to infer_receiver_type" do
      expect(inferrer).to respond_to(:infer_receiver_type)
    end
  end

  describe "#variable_node?" do
    it "returns true for LocalVariableReadNode" do
      # x is parsed as a CallNode (method call) when not defined
      # Let's use a proper local variable
      result = Prism.parse("x = 1; x")
      local_var_read = result.value.statements.body.last
      expect(inferrer.send(:variable_node?, local_var_read)).to be true
    end

    it "returns true for InstanceVariableReadNode" do
      result = Prism.parse("@x")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be true
    end

    it "returns true for ClassVariableReadNode" do
      result = Prism.parse("@@x")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be true
    end

    it "returns true for GlobalVariableReadNode" do
      result = Prism.parse("$x")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be true
    end

    it "returns true for SelfNode" do
      result = Prism.parse("self")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be true
    end

    it "returns false for IntegerNode" do
      result = Prism.parse("42")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be false
    end

    it "returns false for StringNode" do
      result = Prism.parse('"hello"')
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be false
    end

    it "returns false for CallNode" do
      result = Prism.parse("foo()")
      node = result.value.statements.body.first
      expect(inferrer.send(:variable_node?, node)).to be false
    end
  end

  describe "#extract_receiver_variable" do
    it "extracts local variable from call receiver" do
      result = Prism.parse("x = 1; x.to_s")
      call_node = result.value.statements.body.last
      receiver = inferrer.send(:extract_receiver_variable, call_node)
      expect(receiver).to be_a(Prism::LocalVariableReadNode)
      expect(receiver.name).to eq(:x)
    end

    it "extracts instance variable from call receiver" do
      result = Prism.parse("@x.to_s")
      call_node = result.value.statements.body.first
      receiver = inferrer.send(:extract_receiver_variable, call_node)
      expect(receiver).to be_a(Prism::InstanceVariableReadNode)
    end

    it "returns nil for call without receiver" do
      result = Prism.parse("foo()")
      call_node = result.value.statements.body.first
      receiver = inferrer.send(:extract_receiver_variable, call_node)
      expect(receiver).to be_nil
    end

    it "unwraps parenthesized receiver" do
      result = Prism.parse("x = 1; (x).to_s")
      call_node = result.value.statements.body.last
      receiver = inferrer.send(:extract_receiver_variable, call_node)
      expect(receiver).to be_a(Prism::LocalVariableReadNode)
      expect(receiver.name).to eq(:x)
    end
  end

  describe RubyLsp::TypeInferrer::Type do
    describe "#name" do
      it "stores the type name" do
        type = described_class.new("String")
        expect(type.name).to eq("String")
      end
    end

    describe "#attached" do
      it "removes singleton class from name" do
        type = described_class.new("Foo::Bar::<Class:Bar>")
        attached = type.attached
        expect(attached.name).to eq("Foo::Bar")
      end
    end
  end

  describe RubyLsp::TypeInferrer::GuessedType do
    it "inherits from Type" do
      guessed = described_class.new("User")
      expect(guessed).to be_a(RubyLsp::TypeInferrer::Type)
      expect(guessed.name).to eq("User")
    end
  end
end
