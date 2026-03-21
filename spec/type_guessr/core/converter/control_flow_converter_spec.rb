# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "if statement conversion" do
    it "creates merge node for if/else" do
      source = <<~RUBY
        if condition
          x = "hello"
        else
          x = 123
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(node.branches.size).to eq(2)
    end

    it "creates merge node for inline if (modifier if)" do
      source = "x = 1 if condition"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Variable should be a MergeNode with WriteNode and nil
      var = context.lookup_variable(:x)
      expect(var).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(var.branches.size).to eq(2)

      # One branch is LocalWriteNode, one is LiteralNode(nil)
      types = var.branches.map(&:class).map(&:name)
      expect(types).to include("TypeGuessr::Core::IR::LocalWriteNode")
      expect(types).to include("TypeGuessr::Core::IR::LiteralNode")
    end

    it "creates merge node for inline unless (modifier unless)" do
      source = "x = 1 unless condition"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Variable should be a MergeNode with WriteNode and nil
      var = context.lookup_variable(:x)
      expect(var).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(var.branches.size).to eq(2)
    end
  end

  describe "case statements" do
    describe "case/when" do
      it "creates MergeNode for case with multiple when clauses" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then "two"
          else "other"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(3)
        node.branches.each do |branch|
          expect(branch).to be_a(TypeGuessr::Core::IR::LiteralNode)
          expect(branch.type.name).to eq("String")
        end
      end

      it "returns single branch when only one when clause" do
        source = <<~RUBY
          case n
          when 1 then "one"
          else "default"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(2)
      end
    end

    describe "case without else" do
      it "includes nil as possible branch" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then "two"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # 2 when clauses + nil for missing else
        expect(node.branches.size).to eq(3)

        # One of the branches should be nil
        nil_branch = node.branches.find { |b| b.type.name == "NilClass" }
        expect(nil_branch).not_to be_nil
      end
    end

    describe "case with variable assignments" do
      it "creates MergeNode for variables assigned in branches" do
        source = <<~RUBY
          case n
          when 1 then x = "a"
          when 2 then x = "b"
          else x = "c"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        converter.convert(parsed.value.statements.body.first, context)

        # Variable x should be a MergeNode
        x_var = context.lookup_variable(:x)
        expect(x_var).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(x_var.branches.size).to eq(3)
      end
    end

    describe "case without predicate" do
      it "converts case without predicate (like if/elsif chain)" do
        source = <<~RUBY
          case
          when flag then 1
          when other then 2
          else 3
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        expect(node.branches.size).to eq(3)
        node.branches.each do |branch|
          expect(branch).to be_a(TypeGuessr::Core::IR::LiteralNode)
          expect(branch.type.name).to eq("Integer")
        end
      end
    end

    describe "case with empty when clause" do
      it "treats empty when clause as nil" do
        source = <<~RUBY
          case n
          when 1 then
          when 2 then "two"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # Should have 3 branches: nil (empty when), String, nil (no else)
        nil_branches = node.branches.select { |b| b.type.name == "NilClass" }
        expect(nil_branches.size).to be >= 1
      end
    end

    describe "case with non-returning branches" do
      it "excludes raise from branch types" do
        source = <<~RUBY
          case n
          when 1 then "one"
          when 2 then raise "error"
          else "other"
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)

        expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
        # raise branch should be excluded
        expect(node.branches.size).to eq(2)
        node.branches.each do |branch|
          expect(branch.type.name).to eq("String")
        end
      end
    end
  end

  describe "standalone begin/rescue/ensure" do
    it "converts standalone begin/rescue block" do
      source = <<~RUBY
        begin
          risky_operation
        rescue => e
          fallback
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      # Should return the last node from the begin block
      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
    end

    it "converts begin/rescue/else/ensure" do
      source = <<~RUBY
        begin
          main_operation
        rescue
          handle_error
        else
          on_success
        ensure
          cleanup
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      # Should return the last node (from ensure clause)
      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
    end
  end

  describe "OrNode (|| operator)" do
    it "converts || to OrNode with lhs and rhs" do
      source = "a || b"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::OrNode)
      expect(node.lhs).not_to be_nil
      expect(node.rhs).not_to be_nil
    end

    it "converts method with || chain to have proper return_node" do
      source = <<~RUBY
        class Foo
          def lookup(name)
            @cache[name] || @fallback[name]
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      lookup_method = class_node.methods.first
      expect(lookup_method.return_node).to be_a(TypeGuessr::Core::IR::OrNode)
    end

    it "converts predicate method with || chain" do
      source = <<~RUBY
        class Foo
          def valid?(node)
            node.is_a?(String) || node.is_a?(Symbol)
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      valid_method = class_node.methods.first
      expect(valid_method.return_node).to be_a(TypeGuessr::Core::IR::OrNode)
    end
  end

  describe "AndNode (&& operator)" do
    it "converts && to MergeNode with both branches" do
      source = "a && b"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::MergeNode)
      expect(node.branches.size).to eq(2)
    end

    it "converts method with && chain to have proper return_node" do
      source = <<~RUBY
        class Foo
          def eql?(other)
            self.class == other.class && @value == other.value
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      eql_method = class_node.methods.first
      expect(eql_method.return_node).to be_a(TypeGuessr::Core::IR::MergeNode)
    end
  end

  describe "MultiWriteNode (multiple assignment)" do
    it "converts multiple assignment and registers variables" do
      source = "a, b = [1, 2]"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      expect(context.lookup_variable(:a)).not_to be_nil
      expect(context.lookup_variable(:b)).not_to be_nil
    end

    it "creates synthetic [] call nodes for each target" do
      source = "a, b = [1, 2]"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      a_node = context.lookup_variable(:a)
      expect(a_node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
      expect(a_node.value).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(a_node.value.method).to eq(:[])
      expect(a_node.value.args.first.literal_value).to eq(0)

      b_node = context.lookup_variable(:b)
      expect(b_node.value.args.first.literal_value).to eq(1)
    end

    it "converts multiple assignment with splat" do
      source = "first, *rest = array"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      expect(context.lookup_variable(:first)).not_to be_nil
      first_node = context.lookup_variable(:first)
      expect(first_node.value).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(first_node.value.method).to eq(:[])

      rest_node = context.lookup_variable(:rest)
      expect(rest_node).not_to be_nil
      expect(rest_node.value).to be_a(TypeGuessr::Core::IR::LiteralNode)
      expect(rest_node.value.type).to be_a(TypeGuessr::Core::Types::ArrayType)
    end

    it "handles rights after splat with negative indices" do
      source = "first, *middle, last = array"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      first_node = context.lookup_variable(:first)
      expect(first_node.value.args.first.literal_value).to eq(0)

      last_node = context.lookup_variable(:last)
      expect(last_node.value.args.first.literal_value).to eq(-1)
    end
  end

  describe "ParenthesesNode" do
    it "unwraps parenthesized expression" do
      source = "(1 + 2)"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:+)
    end

    it "properly handles assignment from parenthesized expression" do
      source = "x = (a || b)"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::LocalWriteNode)
      expect(node.value).to be_a(TypeGuessr::Core::IR::OrNode)
    end
  end
end
