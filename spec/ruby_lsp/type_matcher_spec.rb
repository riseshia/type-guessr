# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"

RSpec.describe RubyLsp::TypeGuessr::TypeMatcher do
  subject(:matcher) { described_class.new(index) }

  let(:index) { RubyIndexer::Index.new }

  describe "index access" do
    it "can access Ruby LSP's global index" do
      expect(index).not_to be_nil
      expect(index).to respond_to(:[])
    end
  end

  describe "#find_matching_types" do
    context "with classes defining different methods" do
      before do
        source = <<~RUBY
          class Recipe
            def ingredients
              []
            end

            def steps
              []
            end

            def comments
              []
            end
          end

          class Article
            def comments
              []
            end

            def author
              ""
            end
          end

          class Book
            def author
              ""
            end

            def isbn
              ""
            end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake.rb"), source)
      end

      it "finds classes with all specified methods" do
        matches = matcher.find_matching_types(%w[ingredients comments])
        expect(matches).to eq(["Recipe"])
      end

      it "finds all classes with a common method" do
        matches = matcher.find_matching_types(["comments"])
        expect(matches.sort).to eq(%w[Article Recipe])
      end

      it "finds multiple classes with author method" do
        matches = matcher.find_matching_types(["author"])
        expect(matches.sort).to eq(%w[Article Book])
      end
    end

    context "when no class has all methods" do
      before do
        source = <<~RUBY
          class Recipe
            def ingredients
              []
            end
          end

          class Article
            def comments
              []
            end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake2.rb"), source)
      end

      it "returns empty array when no class matches all methods" do
        matches = matcher.find_matching_types(%w[ingredients comments])
        expect(matches).to eq([])
      end

      it "returns empty array for nonexistent method" do
        matches = matcher.find_matching_types(["nonexistent_method"])
        expect(matches).to eq([])
      end
    end

    context "when exactly one class matches" do
      before do
        source = <<~RUBY
          class UniqueClass
            def unique_method_alpha
            end

            def unique_method_beta
            end
          end

          class OtherClass
            def other_method
            end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake3.rb"), source)
      end

      it "returns single class name" do
        matches = matcher.find_matching_types(%w[unique_method_alpha unique_method_beta])
        expect(matches).to eq(["UniqueClass"])
      end
    end

    context "when multiple classes match" do
      before do
        source = <<~RUBY
          class Persisted
            def save
            end

            def destroy
            end
          end

          class Cached
            def save
            end

            def destroy
            end

            def expire
            end
          end

          class Simple
            def process
            end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake4.rb"), source)
      end

      it "returns all matching class names" do
        matches = matcher.find_matching_types(%w[save destroy])
        expect(matches.sort).to eq(%w[Cached Persisted])
      end
    end
  end

  describe "finding methods in class" do
    before do
      source = <<~RUBY
        class TestClass
          def method_one
            "one"
          end

          def method_two
            "two"
          end
        end
      RUBY

      index.index_single(URI::Generic.from_path(path: "/fake.rb"), source)
    end

    it "finds class in the index" do
      entries = index["TestClass"]
      expect(entries).not_to be_nil
      expect(entries).not_to be_empty
    end

    it "returns Class entry type" do
      entries = index["TestClass"]
      class_entry = entries.first
      expect(class_entry).to be_a(RubyIndexer::Entry::Class)
    end

    it "resolves methods for the class" do
      method_one_entries = index.resolve_method("method_one", "TestClass")
      expect(method_one_entries).not_to be_nil
      expect(method_one_entries).not_to be_empty

      method_two_entries = index.resolve_method("method_two", "TestClass")
      expect(method_two_entries).not_to be_nil
      expect(method_two_entries).not_to be_empty
    end

    it "associates methods with correct owner" do
      method_one_entries = index.resolve_method("method_one", "TestClass")
      method_two_entries = index.resolve_method("method_two", "TestClass")

      expect(method_one_entries.first.owner&.name).to eq("TestClass")
      expect(method_two_entries.first.owner&.name).to eq("TestClass")
    end
  end
end
