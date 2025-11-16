# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Guesser
    class TestRBSSignatureIndexer < Minitest::Test
      def setup
        @sig_index = MethodSignatureIndex.instance
        @sig_index.clear
        @indexer = RBSSignatureIndexer.new(@sig_index)
      end

      def teardown
        @sig_index.clear
      end

      def test_index_ruby_core_basic
        # This tests that we can load Ruby core RBS without errors
        # We won't assert specific signatures as they may vary by Ruby version
        @indexer.index_ruby_core

        # Just check that we indexed something
        assert @sig_index.size > 0, "Should have indexed some core methods"
      end

      def test_enumerable_map_signatures
        @indexer.index_ruby_core

        signatures = @sig_index.get_signatures(
          class_name: "Enumerable",
          method_name: "map"
        )

        # Enumerable#map should have at least one signature
        refute_empty signatures, "Enumerable#map should have signatures"

        # Check that we have both return types (with and without block)
        return_types = signatures.map { |sig| sig[:return_type] }.uniq
        assert return_types.size > 0, "Should have at least one return type"
      end

      def test_string_upcase_signature
        @indexer.index_ruby_core

        signatures = @sig_index.get_signatures(
          class_name: "String",
          method_name: "upcase"
        )

        refute_empty signatures, "String#upcase should have signatures"

        # At least one signature should return String
        return_types = signatures.map { |sig| sig[:return_type] }
        assert return_types.any? { |t| t.include?("String") }, "Should return String"
      end

      def test_singleton_method
        @indexer.index_ruby_core

        # Array.[] is a class method (singleton)
        signatures = @sig_index.get_signatures(
          class_name: "Array",
          method_name: "[]",
          singleton: true
        )

        refute_empty signatures, "Array.[] should have signatures"

        # Check that it returns an Array
        return_types = signatures.map { |sig| sig[:return_type] }
        assert return_types.any? { |t| t.include?("Array") }, "Should return Array"
      end

      def test_get_return_types_helper
        @indexer.index_ruby_core

        return_types = @sig_index.get_return_types(
          class_name: "Array",
          method_name: "first"
        )

        refute_empty return_types, "Array#first should have return types"
      end
    end
  end
end
