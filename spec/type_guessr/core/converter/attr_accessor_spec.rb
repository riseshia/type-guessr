# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  def convert_class(source)
    parsed = Prism.parse(source)
    context = TypeGuessr::Core::Converter::PrismConverter::Context.new
    converter.convert(parsed.value.statements.body.first, context)
  end

  describe "attr_reader synthesis" do
    it "synthesizes DefNode for single attr_reader" do
      source = <<~RUBY
        class Recipe
          attr_reader :name
        end
      RUBY
      node = convert_class(source)

      expect(node).to be_a(TypeGuessr::Core::IR::ClassModuleNode)
      reader = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::DefNode) && m.name == :name }
      expect(reader).not_to be_nil
      expect(reader.params).to be_empty
      expect(reader.singleton).to be(false)
      expect(reader.return_node).to be_a(TypeGuessr::Core::IR::InstanceVariableReadNode)
      expect(reader.return_node.name).to eq(:@name)
      expect(reader.return_node.class_name).to eq("Recipe")
    end

    it "synthesizes DefNodes for multiple attr_reader arguments" do
      source = <<~RUBY
        class Recipe
          attr_reader :name, :age
        end
      RUBY
      node = convert_class(source)

      def_names = node.methods.grep(TypeGuessr::Core::IR::DefNode).map(&:name)
      expect(def_names).to contain_exactly(:name, :age)
    end

    it "accepts string arguments" do
      source = <<~RUBY
        class Recipe
          attr_reader "name"
        end
      RUBY
      node = convert_class(source)

      reader = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::DefNode) }
      expect(reader).not_to be_nil
      expect(reader.name).to eq(:name)
      expect(reader.return_node.name).to eq(:@name)
    end

    it "skips non-literal arguments" do
      source = <<~RUBY
        class Recipe
          FIELDS = [:name]
          attr_reader(*FIELDS)
        end
      RUBY
      node = convert_class(source)

      defs = node.methods.grep(TypeGuessr::Core::IR::DefNode)
      expect(defs).to be_empty
    end

    it "uses symbol argument location for DefNode loc" do
      source = <<~RUBY
        class Recipe
          attr_reader :name
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      reader = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::DefNode) && m.name == :name }
      expected_offset = source.index(":name")
      expect(reader.loc).to eq(expected_offset)
    end
  end

  describe "attr_writer synthesis" do
    it "synthesizes DefNode for attr_writer with setter name" do
      source = <<~RUBY
        class Recipe
          attr_writer :name
        end
      RUBY
      node = convert_class(source)

      writer = node.methods.find { |m| m.is_a?(TypeGuessr::Core::IR::DefNode) && m.name == :name= }
      expect(writer).not_to be_nil
      expect(writer.params.size).to eq(1)
      expect(writer.params.first.name).to eq(:value)
      expect(writer.params.first.kind).to eq(:required)
      expect(writer.return_node).to eq(writer.params.first)
    end
  end

  describe "attr_accessor synthesis" do
    it "synthesizes both reader and writer DefNodes" do
      source = <<~RUBY
        class Recipe
          attr_accessor :name
        end
      RUBY
      node = convert_class(source)

      def_names = node.methods.grep(TypeGuessr::Core::IR::DefNode).map(&:name)
      expect(def_names).to contain_exactly(:name, :name=)
    end

    it "handles multiple arguments for accessor" do
      source = <<~RUBY
        class Recipe
          attr_accessor :name, :age
        end
      RUBY
      node = convert_class(source)

      def_names = node.methods.grep(TypeGuessr::Core::IR::DefNode).map(&:name)
      expect(def_names).to contain_exactly(:name, :name=, :age, :age=)
    end
  end

  describe "method registration via attr_*" do
    it "registers synthesized reader in method_registry" do
      method_registry = TypeGuessr::Core::Registry::MethodRegistry.new
      ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new
      location_index = TypeGuessr::Core::Index::LocationIndex.new
      source = <<~RUBY
        class Recipe
          attr_reader :name
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
        file_path: "recipe.rb",
        location_index: location_index,
        method_registry: method_registry,
        ivar_registry: ivar_registry
      )
      converter.convert(parsed.value.statements.body.first, context)

      def_node = method_registry.lookup("Recipe", "name")
      expect(def_node).not_to be_nil
      expect(def_node.name).to eq(:name)
    end

    it "registers synthesized writer in method_registry" do
      method_registry = TypeGuessr::Core::Registry::MethodRegistry.new
      ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new
      location_index = TypeGuessr::Core::Index::LocationIndex.new
      source = <<~RUBY
        class Recipe
          attr_accessor :name
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
        file_path: "recipe.rb",
        location_index: location_index,
        method_registry: method_registry,
        ivar_registry: ivar_registry
      )
      converter.convert(parsed.value.statements.body.first, context)

      expect(method_registry.lookup("Recipe", "name")).not_to be_nil
      expect(method_registry.lookup("Recipe", "name=")).not_to be_nil
    end
  end
end
