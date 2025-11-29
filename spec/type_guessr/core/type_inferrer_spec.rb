# frozen_string_literal: true

require "spec_helper"

RSpec.describe TypeGuessr::Core::TypeInferrer do
  subject(:inferrer) { described_class.new(index) }

  let(:index) { RubyIndexer::Index.new }

  describe "inheritance" do
    it "inherits from RubyLsp::TypeInferrer" do
      expect(inferrer).to be_a(RubyLsp::TypeInferrer)
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
