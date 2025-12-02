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

    context "when more than MAX_MATCHING_TYPES classes match" do
      before do
        source = <<~RUBY
          class ClassA
            def common_method; end
          end

          class ClassB
            def common_method; end
          end

          class ClassC
            def common_method; end
          end

          class ClassD
            def common_method; end
          end

          class ClassE
            def common_method; end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake5.rb"), source)
      end

      it "truncates results and adds marker when more than 3 classes match" do
        matches = matcher.find_matching_types(["common_method"])
        # Should return exactly MAX_MATCHING_TYPES (3) classes plus the truncation marker
        expect(matches.size).to eq(4)
        expect(matches.last).to eq(RubyLsp::TypeGuessr::TypeMatcher::TRUNCATED_MARKER)
        # The first 3 should be actual class names (order may vary)
        expect(matches[0..2]).to all(match(/^Class[A-E]$/))
      end

      it "returns all results when exactly MAX_MATCHING_TYPES match" do
        # Remove 2 classes to have exactly 3 matching
        source = <<~RUBY
          class ClassX
            def exact_method; end
          end

          class ClassY
            def exact_method; end
          end

          class ClassZ
            def exact_method; end
          end
        RUBY

        index.index_single(URI::Generic.from_path(path: "/fake6.rb"), source)

        matches = matcher.find_matching_types(["exact_method"])
        expect(matches.size).to eq(3)
        expect(matches).not_to include(RubyLsp::TypeGuessr::TypeMatcher::TRUNCATED_MARKER)
        expect(matches.sort).to eq(%w[ClassX ClassY ClassZ])
      end
    end
  end

  describe "with inheritance" do
    before do
      source = <<~RUBY
        class Recipe
          def ingredients
            []
          end
        end

        class Recipe2 < Recipe
          def steps
            []
          end
        end
      RUBY

      index.index_single(URI::Generic.from_path(path: "/inheritance.rb"), source)
    end

    it "finds subclass that has inherited method and own method" do
      matches = matcher.find_matching_types(%w[ingredients steps])
      expect(matches).to eq(["Recipe2"])
    end

    it "finds parent class when only parent methods are called" do
      matches = matcher.find_matching_types(["ingredients"])
      expect(matches).to eq(["Recipe"])
    end

    it "excludes parent class when it lacks subclass methods" do
      matches = matcher.find_matching_types(%w[ingredients steps])
      expect(matches).not_to include("Recipe")
    end
  end

  describe "with method override in subclasses" do
    before do
      source = <<~RUBY
        class Animal
          def eat; end
        end

        class Dog < Animal
          def eat; end
          def bark; end
        end

        class Cat < Animal
          def eat; end
          def meow; end
        end
      RUBY

      index.index_single(URI::Generic.from_path(path: "/override.rb"), source)
    end

    it "reduces overriding subclasses to common ancestor" do
      matches = matcher.find_matching_types(["eat"])
      # Dog and Cat both override eat, but Animal is the common ancestor
      expect(matches).to eq(["Animal"])
    end

    it "returns specific class when subclass-only method is included" do
      matches = matcher.find_matching_types(%w[eat bark])
      expect(matches).to eq(["Dog"])
    end
  end

  describe "with mixins" do
    before do
      source = <<~RUBY
        module Commentable
          def comments; end
        end

        module Likeable
          def likes; end
        end

        class Recipe
          include Commentable
          def ingredients; end
        end

        class Article
          include Commentable
          include Likeable
          def author; end
        end

        class Post
          include Likeable
          def title; end
        end
      RUBY

      index.index_single(URI::Generic.from_path(path: "/mixins.rb"), source)
    end

    it "finds class with mixin method and own method" do
      matches = matcher.find_matching_types(%w[comments ingredients])
      expect(matches).to eq(["Recipe"])
    end

    it "finds class when class method is combined with mixin method" do
      matches = matcher.find_matching_types(%w[author comments])
      expect(matches).to eq(["Article"])
    end

    it "finds class when own method owner is collected and mixin is resolved" do
      matches = matcher.find_matching_types(%w[likes author])
      expect(matches).to eq(["Article"])
    end

    # NOTE: This is a known limitation of the current algorithm.
    # When all methods come from mixins (no class-defined methods in the query),
    # we cannot find the class that includes both modules.
    # This would require reverse-lookup of module includers, which is expensive.
    # If this becomes a common need, consider building a dedicated includers index.
    it "cannot find class when all methods come from mixins (known limitation)" do
      matches = matcher.find_matching_types(%w[comments likes])
      # Article includes both Commentable and Likeable, but we can't find it
      # because neither module is a class and they don't include each other
      expect(matches).to eq([])
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
