# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/flow_analyzer"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::FlowAnalyzer do
  let(:analyzer) { described_class.new }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  describe "simple assignment tracking" do
    it "infers type from simple literal assignment" do
      source = <<~RUBY
        x = "hello"
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line2 = result.type_at(2, 0, "x") # Line 2, column 0 is the 'x' reference

      expect(type_at_line2).to eq(string_type)
    end

    it "tracks type changes through reassignment" do
      source = <<~RUBY
        x = "hello"
        x = 42
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line3 = result.type_at(3, 0, "x")

      expect(type_at_line3).to eq(integer_type)
    end

    it "returns Unknown for unassigned variables" do
      source = <<~RUBY
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line1 = result.type_at(1, 0, "x")

      expect(type_at_line1).to eq(unknown_type)
    end
  end

  describe "branch merge" do
    it "creates union type at join point after if/else" do
      source = <<~RUBY
        if condition
          x = "hello"
        else
          x = 42
        end
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line6 = result.type_at(6, 0, "x")

      expect(type_at_line6).to be_a(TypeGuessr::Core::Types::Union)
      expect(type_at_line6.types).to contain_exactly(string_type, integer_type)
    end

    it "handles if without else (union with Unknown)" do
      source = <<~RUBY
        if condition
          x = "hello"
        end
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line4 = result.type_at(4, 0, "x")

      # x might be String or Unknown (if branch not taken)
      expect(type_at_line4).to be_a(TypeGuessr::Core::Types::Union)
      expect(type_at_line4.types).to include(string_type)
    end
  end

  describe "short-circuit assignment" do
    it "handles ||= operator" do
      source = <<~RUBY
        x = "hello"
        x ||= 42
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line3 = result.type_at(3, 0, "x")

      # x is either String (if truthy) or Integer (if falsy, which won't happen for String)
      # For simplicity, we union them
      expect(type_at_line3).to be_a(TypeGuessr::Core::Types::Union)
      expect(type_at_line3.types).to contain_exactly(string_type, integer_type)
    end

    it "handles &&= operator" do
      source = <<~RUBY
        x = "hello"
        x &&= 42
        x
      RUBY

      result = analyzer.analyze(source)
      type_at_line3 = result.type_at(3, 0, "x")

      # x is either String (if falsy, which won't happen) or Integer (if truthy)
      expect(type_at_line3).to be_a(TypeGuessr::Core::Types::Union)
      expect(type_at_line3.types).to contain_exactly(string_type, integer_type)
    end
  end

  describe "return type inference" do
    it "infers return type from explicit return statement" do
      source = <<~RUBY
        def foo
          return "hello"
        end
      RUBY

      result = analyzer.analyze(source)
      return_type = result.return_type_for_method("foo")

      expect(return_type).to eq(string_type)
    end

    it "infers return type from last expression" do
      source = <<~RUBY
        def foo
          42
        end
      RUBY

      result = analyzer.analyze(source)
      return_type = result.return_type_for_method("foo")

      expect(return_type).to eq(integer_type)
    end

    it "creates union of multiple return paths" do
      source = <<~RUBY
        def foo
          if condition
            return "hello"
          end
          42
        end
      RUBY

      result = analyzer.analyze(source)
      return_type = result.return_type_for_method("foo")

      expect(return_type).to be_a(TypeGuessr::Core::Types::Union)
      expect(return_type.types).to contain_exactly(string_type, integer_type)
    end

    it "infers NilClass from empty method body" do
      source = <<~RUBY
        def eat
        end
      RUBY

      result = analyzer.analyze(source)
      return_type = result.return_type_for_method("eat")

      expect(return_type).to eq(TypeGuessr::Core::Types::ClassInstance.new("NilClass"))
    end
  end
end
