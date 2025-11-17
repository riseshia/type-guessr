# frozen_string_literal: true

require "test_helper"
require "ruby_lsp/internal"

module RubyLsp
  module TypeGuessr
    class TestTypeMatcher < Minitest::Test
      def setup
        @index = RubyIndexer::Index.new
      end

      def test_can_access_global_index
        # Phase 1, Test 1: Can access Ruby LSP's global index to query class/module definitions
        # The index should be accessible and respond to basic queries
        refute_nil @index
        assert_respond_to @index, :[]
      end

      def test_find_classes_with_all_methods
        # Phase 2, Test 1: Given a set of method names, can find all classes that have ALL those methods
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

        @index.index_single(URI::Generic.from_path(path: "/fake.rb"), source)

        # Create a TypeMatcher instance
        matcher = RubyLsp::TypeGuessr::TypeMatcher.new(@index)

        # Find classes that have both 'ingredients' and 'comments' methods
        # Only Recipe should match
        matches = matcher.find_matching_types(%w[ingredients comments])
        assert_equal ["Recipe"], matches.sort

        # Find classes that have 'comments' method
        # Both Recipe and Article should match
        matches = matcher.find_matching_types(["comments"])
        assert_equal %w[Article Recipe], matches.sort

        # Find classes that have 'author' method
        # Both Article and Book should match
        matches = matcher.find_matching_types(["author"])
        assert_equal %w[Article Book], matches.sort
      end

      def test_returns_empty_when_no_class_has_all_methods
        # Phase 2, Test 2: Returns empty array when no class has all the methods
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

        @index.index_single(URI::Generic.from_path(path: "/fake2.rb"), source)

        matcher = RubyLsp::TypeGuessr::TypeMatcher.new(@index)

        # No class has both 'ingredients' and 'comments'
        matches = matcher.find_matching_types(%w[ingredients comments])
        assert_equal [], matches

        # No class has 'nonexistent_method'
        matches = matcher.find_matching_types(["nonexistent_method"])
        assert_equal [], matches
      end

      def test_returns_single_class_when_exactly_one_matches
        # Phase 2, Test 3: Returns single class name when exactly one match exists
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

        @index.index_single(URI::Generic.from_path(path: "/fake3.rb"), source)

        matcher = RubyLsp::TypeGuessr::TypeMatcher.new(@index)

        # Only UniqueClass has both methods
        matches = matcher.find_matching_types(%w[unique_method_alpha unique_method_beta])
        assert_equal ["UniqueClass"], matches
      end

      def test_returns_multiple_classes_when_multiple_match
        # Phase 2, Test 4: Returns multiple class names when multiple matches exist
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

        @index.index_single(URI::Generic.from_path(path: "/fake4.rb"), source)

        matcher = RubyLsp::TypeGuessr::TypeMatcher.new(@index)

        # Both Persisted and Cached have 'save' and 'destroy'
        matches = matcher.find_matching_types(%w[save destroy])
        assert_equal %w[Cached Persisted], matches.sort
      end

      def test_can_find_methods_in_class
        # Phase 1, Test 2: Can find all methods defined in a specific class from the index
        # Create a simple class with a couple of methods
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

        # Index the source
        @index.index_single(URI::Generic.from_path(path: "/fake.rb"), source)

        # Query the index for TestClass
        entries = @index["TestClass"]
        refute_nil entries, "Should find TestClass in the index"
        refute_empty entries, "Should have at least one entry for TestClass"

        # Get the class entry
        class_entry = entries.first
        assert_instance_of RubyIndexer::Entry::Class, class_entry

        # Use resolve_method to find specific methods
        method_one_entries = @index.resolve_method("method_one", "TestClass")
        refute_nil method_one_entries, "Should find method_one"
        refute_empty method_one_entries, "Should have at least one entry for method_one"

        method_two_entries = @index.resolve_method("method_two", "TestClass")
        refute_nil method_two_entries, "Should find method_two"
        refute_empty method_two_entries, "Should have at least one entry for method_two"

        # Verify the methods belong to TestClass
        assert_equal "TestClass", method_one_entries.first.owner&.name
        assert_equal "TestClass", method_two_entries.first.owner&.name
      end
    end
  end
end
