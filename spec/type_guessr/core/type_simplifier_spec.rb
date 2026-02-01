# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/type_simplifier"
require "type_guessr/core/types"

RSpec.describe TypeGuessr::Core::TypeSimplifier do
  let(:simplifier) { described_class.new }

  describe "#simplify" do
    context "when type is not a Union" do
      it "returns ClassInstance unchanged" do
        type = TypeGuessr::Core::Types::ClassInstance.new("String")
        expect(simplifier.simplify(type)).to be(type)
      end

      it "returns Unknown unchanged" do
        type = TypeGuessr::Core::Types::Unknown.instance
        expect(simplifier.simplify(type)).to be(type)
      end

      it "returns ArrayType unchanged" do
        type = TypeGuessr::Core::Types::ArrayType.new
        expect(simplifier.simplify(type)).to be(type)
      end
    end

    context "when Union has single element" do
      it "unwraps single ClassInstance" do
        type = TypeGuessr::Core::Types::ClassInstance.new("String")
        union = TypeGuessr::Core::Types::Union.new([type])

        result = simplifier.simplify(union)

        expect(result).to eq(type)
        expect(result).to be_a(TypeGuessr::Core::Types::ClassInstance)
      end

      it "unwraps single Unknown" do
        unknown = TypeGuessr::Core::Types::Unknown.instance
        union = TypeGuessr::Core::Types::Union.new([unknown])

        result = simplifier.simplify(union)

        expect(result).to be(unknown)
      end

      it "unwraps single ArrayType" do
        array_type = TypeGuessr::Core::Types::ArrayType.new(
          TypeGuessr::Core::Types::ClassInstance.new("Integer")
        )
        union = TypeGuessr::Core::Types::Union.new([array_type])

        result = simplifier.simplify(union)

        expect(result).to eq(array_type)
      end
    end

    context "when Union has multiple elements" do
      it "returns Union unchanged when elements are unrelated" do
        type1 = TypeGuessr::Core::Types::ClassInstance.new("String")
        type2 = TypeGuessr::Core::Types::ClassInstance.new("Integer")
        union = TypeGuessr::Core::Types::Union.new([type1, type2])

        result = simplifier.simplify(union)

        expect(result).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.types).to contain_exactly(type1, type2)
      end

      it "returns Unknown when Union has more than MAX_ELEMENT_IN_UNION elements" do
        types = %w[A B C D].map { |name| TypeGuessr::Core::Types::ClassInstance.new(name) }
        union = TypeGuessr::Core::Types::Union.new(types)

        result = simplifier.simplify(union)

        expect(result).to be_a(TypeGuessr::Core::Types::Unknown)
      end

      it "keeps Union when exactly MAX_ELEMENT_IN_UNION elements" do
        types = %w[A B C].map { |name| TypeGuessr::Core::Types::ClassInstance.new(name) }
        union = TypeGuessr::Core::Types::Union.new(types)

        result = simplifier.simplify(union)

        expect(result).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.types.size).to eq(3)
      end
    end

    context "with code_index" do
      # Mock code_index: Dog < Animal, Cat < Animal
      let(:code_index) do
        double.tap do |idx|
          allow(idx).to receive(:ancestors_of).and_return([])
          allow(idx).to receive(:ancestors_of).with("Dog").and_return(%w[Dog Animal Object])
          allow(idx).to receive(:ancestors_of).with("Cat").and_return(%w[Cat Animal Object])
          allow(idx).to receive(:ancestors_of).with("Animal").and_return(%w[Animal Object])
          allow(idx).to receive(:ancestors_of).with("Object").and_return(["Object"])
        end
      end

      let(:simplifier) { described_class.new(code_index: code_index) }

      it "unifies child to parent when parent is also in union" do
        animal = TypeGuessr::Core::Types::ClassInstance.new("Animal")
        dog = TypeGuessr::Core::Types::ClassInstance.new("Dog")
        union = TypeGuessr::Core::Types::Union.new([animal, dog])

        result = simplifier.simplify(union)

        expect(result).to eq(animal)
      end

      it "unifies multiple children to parent" do
        animal = TypeGuessr::Core::Types::ClassInstance.new("Animal")
        dog = TypeGuessr::Core::Types::ClassInstance.new("Dog")
        cat = TypeGuessr::Core::Types::ClassInstance.new("Cat")
        union = TypeGuessr::Core::Types::Union.new([animal, dog, cat])

        result = simplifier.simplify(union)

        expect(result).to eq(animal)
      end

      it "keeps siblings when parent is not in union" do
        dog = TypeGuessr::Core::Types::ClassInstance.new("Dog")
        cat = TypeGuessr::Core::Types::ClassInstance.new("Cat")
        union = TypeGuessr::Core::Types::Union.new([dog, cat])

        result = simplifier.simplify(union)

        expect(result).to be_a(TypeGuessr::Core::Types::Union)
        expect(result.types).to contain_exactly(dog, cat)
      end

      it "handles non-ClassInstance types in union" do
        animal = TypeGuessr::Core::Types::ClassInstance.new("Animal")
        unknown = TypeGuessr::Core::Types::Unknown.instance
        union = TypeGuessr::Core::Types::Union.new([animal, unknown])

        # Unknown simplification happens in Union.normalize, result is just Unknown
        # But TypeSimplifier should still handle this gracefully
        result = simplifier.simplify(union)

        expect(result).to be(unknown)
      end
    end
  end
end
