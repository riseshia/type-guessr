# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "variable assignment" do
    it "converts local variable assignment" do
      source = 'x = "hello"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
      expect(node.name).to eq(:x)
      expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(node.value.type.name).to eq("String")
    end

    it "converts instance variable assignment" do
      source = '@name = "John"'
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
      expect(node.name).to eq(:@name)
    end

    it "converts class variable assignment" do
      source = "@@count = 0"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::ClassVariableWriteNode)
      expect(node.name).to eq(:@@count)
    end
  end

  describe "variable read" do
    it "looks up variable from context" do
      source = <<~RUBY
        x = "hello"
        x
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert assignment
      assignment = parsed.value.statements.body[0]
      write_node = converter.convert(assignment, context)

      # Convert read
      read = parsed.value.statements.body[1]
      read_node = converter.convert(read, context)

      # Read creates a LocalReadNode pointing to the LocalWriteNode
      expect(read_node).to be_a(TypeGuessr::Core::IR::LocalReadNode)
      expect(read_node.write_node).to eq(write_node)
      # Should share called_methods array for duck typing
      expect(read_node.called_methods).to be(write_node.called_methods)
    end
  end

  describe "instance variable called_methods sharing" do
    it "shares called_methods with parameter when assigned from parameter" do
      source = <<~RUBY
        class Foo
          def initialize(adapter)
            @adapter = adapter
          end

          def process
            @adapter.call_method
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      # Get the initialize method's parameter
      init_method = class_node.methods.find { |m| m.name == :initialize }
      param_node = init_method.params.first

      # The InstanceVariableWriteNode should share called_methods with the ParamNode
      # When @adapter.call_method is called, :call_method should be in param's called_methods
      expect(param_node.called_methods.map(&:name)).to include(:call_method)
    end
  end

  describe "class variable called_methods sharing" do
    it "shares called_methods with parameter when assigned from parameter" do
      source = <<~RUBY
        class Foo
          def setup(adapter)
            @@adapter = adapter
            @@adapter.call_method
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      # Get the setup method's parameter
      setup_method = class_node.methods.find { |m| m.name == :setup }
      param_node = setup_method.params.first

      # The ClassVariableWriteNode should share called_methods with the ParamNode
      expect(param_node.called_methods.map(&:name)).to include(:call_method)
    end
  end

  describe "compound assignments" do
    describe "local variable ||= (or-assign)" do
      it "creates LocalWriteNode with value for undefined variable" do
        source = "x ||= 1"
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        # For undefined variable, value is just the RHS
        expect(node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end

      it "creates OrNode for defined variable" do
        source = <<~RUBY
          x = nil
          x ||= 1
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        # Convert first assignment
        converter.convert(parsed.value.statements.body[0], context)

        # Convert ||=
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        # Should be OrNode with lhs (original) and rhs (new value)
        expect(node.value).to be_a(TypeGuessr::Core::IR::OrNode)
        expect(node.value.lhs).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value.rhs).to be_a(TypeGuessr::Core::IR::LiteralNode)
      end
    end

    describe "local variable &&= (and-assign)" do
      it "creates LocalWriteNode with value for undefined variable" do
        source = 'x &&= "string"'
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
      end

      it "creates MergeNode for defined variable" do
        source = <<~RUBY
          x = "hello"
          x &&= "world"
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.value.branches.size).to eq(2)
      end
    end

    describe "local variable operator writes (+=, -=, *=, /=)" do
      it "creates CallNode for +=" do
        source = <<~RUBY
          x = 1
          x += 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.name).to eq(:x)
        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:+)
        expect(node.value.args.size).to eq(1)
      end

      it "creates CallNode for -=" do
        source = <<~RUBY
          count = 10
          count -= 1
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:-)
      end

      it "creates CallNode for *=" do
        source = <<~RUBY
          x = 5
          x *= 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:*)
      end

      it "creates CallNode for /=" do
        source = <<~RUBY
          x = 10
          x /= 2
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.value.method).to eq(:/)
      end
    end

    describe "index ||= (IndexOrWriteNode)" do
      it "creates OrNode with CallNode(:[]) as LHS" do
        source = <<~RUBY
          h = {}
          h[:a] ||= 1
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new

        converter.convert(parsed.value.statements.body[0], context)
        node = converter.convert(parsed.value.statements.body[1], context)

        expect(node).to be_a(TypeGuessr::Core::IR::OrNode)
        expect(node.lhs).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(node.lhs.method).to eq(:[])
        expect(node.rhs).to be_a(TypeGuessr::Core::IR::LiteralNode)
        expect(node.rhs.type.name).to eq("Integer")
      end
    end

    describe "instance variable ||=" do
      it "creates InstanceVariableWriteNode with OrNode for defined variable" do
        source = <<~RUBY
          class Foo
            def setup
              @cache = nil
              @cache ||= {}
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        setup_method = class_node.methods.first
        # The body should contain both assignments
        body_nodes = setup_method.body_nodes

        # Second node should be the ||= assignment
        or_write_node = body_nodes[1]
        expect(or_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(or_write_node.name).to eq(:@cache)
        expect(or_write_node.value).to be_a(TypeGuessr::Core::IR::OrNode)
      end
    end

    describe "instance variable &&=" do
      it "creates InstanceVariableWriteNode with MergeNode" do
        source = <<~RUBY
          class Foo
            def process
              @value = "initial"
              @value &&= "updated"
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        process_method = class_node.methods.first
        and_write_node = process_method.body_nodes[1]

        expect(and_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(and_write_node.name).to eq(:@value)
        expect(and_write_node.value).to be_a(TypeGuessr::Core::IR::MergeNode)
      end
    end

    describe "instance variable operator writes" do
      it "creates InstanceVariableWriteNode with CallNode for +=" do
        source = <<~RUBY
          class Foo
            def increment
              @count = 0
              @count += 1
            end
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        class_node = converter.convert(parsed.value.statements.body.first, context)

        increment_method = class_node.methods.first
        op_write_node = increment_method.body_nodes[1]

        expect(op_write_node).to be_a(TypeGuessr::Core::IR::InstanceVariableWriteNode)
        expect(op_write_node.name).to eq(:@count)
        expect(op_write_node.value).to be_a(TypeGuessr::Core::IR::CallNode)
        expect(op_write_node.value.method).to eq(:+)
      end
    end
  end

  describe "instance variable assignment with unhandled value node" do
    it "handles nil value_node gracefully when value is an unhandled node type" do
      # ForwardingSuperNode is not handled by convert(), returning nil
      # This should not crash when accessing called_methods
      source = <<~RUBY
        class Child < Parent
          def initialize(name)
            @name = super
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Should not raise NoMethodError: undefined method 'called_methods' for nil
      expect { converter.convert(parsed.value.statements.body.first, context) }.not_to raise_error
    end
  end
end
