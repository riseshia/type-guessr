# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Guesser
    class TestMethodSignatureIndex < Minitest::Test
      def setup
        @index = MethodSignatureIndex.instance
        @index.clear
      end

      def teardown
        @index.clear
      end

      def test_add_and_get_signature
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User",
          singleton: true
        )

        signatures = @index.get_signatures(
          class_name: "User",
          method_name: "find",
          singleton: true
        )

        assert_equal 1, signatures.size
        assert_equal 1, signatures.first[:params].size
        assert_equal "id", signatures.first[:params][0][:name]
        assert_equal "Integer", signatures.first[:params][0][:type]
        assert_equal :required, signatures.first[:params][0][:kind]
        assert_equal "User", signatures.first[:return_type]
      end

      def test_multiple_signatures_for_overloads
        @index.add_signature(
          class_name: "Array",
          method_name: "map",
          params: [{ name: "block", type: "Proc", kind: :block, required: true }],
          return_type: "Array[U]"
        )
        @index.add_signature(
          class_name: "Array",
          method_name: "map",
          params: [],
          return_type: "Enumerator[T]"
        )

        signatures = @index.get_signatures(
          class_name: "Array",
          method_name: "map"
        )

        assert_equal 2, signatures.size
        assert_equal 1, signatures[0][:params].size
        assert_equal :block, signatures[0][:params][0][:kind]
        assert_equal "Array[U]", signatures[0][:return_type]
        assert_equal 0, signatures[1][:params].size
        assert_equal "Enumerator[T]", signatures[1][:return_type]
      end

      def test_get_return_types
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User"
        )
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "email", type: "String", kind: :required }],
          return_type: "User"
        )

        return_types = @index.get_return_types(
          class_name: "User",
          method_name: "find"
        )

        assert_equal ["User"], return_types
      end

      def test_singleton_vs_instance_methods
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User",
          singleton: true
        )
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "name", type: "String", kind: :required }],
          return_type: "String",
          singleton: false
        )

        class_sigs = @index.get_signatures(
          class_name: "User",
          method_name: "find",
          singleton: true
        )
        instance_sigs = @index.get_signatures(
          class_name: "User",
          method_name: "find",
          singleton: false
        )

        assert_equal 1, class_sigs.size
        assert_equal "User", class_sigs.first[:return_type]

        assert_equal 1, instance_sigs.size
        assert_equal "String", instance_sigs.first[:return_type]
      end

      def test_get_nonexistent_method
        signatures = @index.get_signatures(
          class_name: "Foo",
          method_name: "bar"
        )

        assert_equal [], signatures
      end

      def test_duplicate_signatures_are_ignored
        @index.add_signature(
          class_name: "User",
          method_name: "name",
          params: [],
          return_type: "String"
        )
        @index.add_signature(
          class_name: "User",
          method_name: "name",
          params: [],
          return_type: "String"
        )

        signatures = @index.get_signatures(
          class_name: "User",
          method_name: "name"
        )

        assert_equal 1, signatures.size
      end

      def test_size
        assert_equal 0, @index.size

        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User"
        )

        assert_equal 1, @index.size

        @index.add_signature(
          class_name: "Post",
          method_name: "all",
          params: [],
          return_type: "Array[Post]"
        )

        assert_equal 2, @index.size
      end

      def test_clear
        @index.add_signature(
          class_name: "User",
          method_name: "find",
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User"
        )

        assert_equal 1, @index.size

        @index.clear

        assert_equal 0, @index.size
      end
    end
  end
end
