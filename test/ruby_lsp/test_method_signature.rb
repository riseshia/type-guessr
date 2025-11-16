# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Guesser
    class TestMethodSignature < Minitest::Test
      def test_create_signature
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "name", type: "String", kind: :optional)
        ]
        sig = MethodSignature.new(params: params, return_type: "User")

        assert_equal 2, sig.params.size
        assert_equal "User", sig.return_type
      end

      def test_positional_params
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "age", type: "Integer", kind: :keyword),
          Parameter.new(name: "name", type: "String", kind: :optional)
        ]
        sig = MethodSignature.new(params: params, return_type: "User")

        positional = sig.positional_params
        assert_equal 2, positional.size
        assert positional.all?(&:positional?)
      end

      def test_keyword_params
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "age", type: "Integer", kind: :keyword),
          Parameter.new(name: "name", type: "String", kind: :optional_keyword)
        ]
        sig = MethodSignature.new(params: params, return_type: "User")

        keywords = sig.keyword_params
        assert_equal 2, keywords.size
        assert keywords.all?(&:keyword?)
      end

      def test_block_param
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "block", type: "Proc", kind: :block, required: true)
        ]
        sig = MethodSignature.new(params: params, return_type: "Array[U]")

        assert sig.block?
        assert sig.block_required?
        assert_equal "block", sig.block_param.name
      end

      def test_no_block
        params = [Parameter.new(name: "id", type: "Integer", kind: :required)]
        sig = MethodSignature.new(params: params, return_type: "User")

        refute sig.block?
        refute sig.block_required?
        assert_nil sig.block_param
      end

      def test_required_positional_count
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "name", type: "String", kind: :optional),
          Parameter.new(name: "args", type: "Integer", kind: :rest)
        ]
        sig = MethodSignature.new(params: params, return_type: "User")

        assert_equal 1, sig.required_positional_count
      end

      def test_to_s
        params = [
          Parameter.new(name: "id", type: "Integer", kind: :required),
          Parameter.new(name: "name", type: "String", kind: :optional)
        ]
        sig = MethodSignature.new(params: params, return_type: "User")

        assert_equal "(Integer id, ?String name) -> User", sig.to_s
      end

      def test_to_s_no_params
        sig = MethodSignature.new(params: [], return_type: "User")
        assert_equal "() -> User", sig.to_s
      end

      def test_to_h
        params = [Parameter.new(name: "id", type: "Integer", kind: :required)]
        sig = MethodSignature.new(params: params, return_type: "User")

        hash = sig.to_h
        assert_equal 1, hash[:params].size
        assert_equal "id", hash[:params][0][:name]
        assert_equal "Integer", hash[:params][0][:type]
        assert_equal :required, hash[:params][0][:kind]
        assert_equal "User", hash[:return_type]
      end

      def test_from_hash
        hash = {
          params: [{ name: "id", type: "Integer", kind: :required }],
          return_type: "User"
        }
        sig = MethodSignature.from_hash(hash)

        assert_equal 1, sig.params.size
        assert_instance_of Parameter, sig.params[0]
        assert_equal "id", sig.params[0].name
        assert_equal "User", sig.return_type
      end

      def test_equality
        params1 = [Parameter.new(name: "id", type: "Integer", kind: :required)]
        params2 = [Parameter.new(name: "id", type: "Integer", kind: :required)]
        params3 = [Parameter.new(name: "id", type: "String", kind: :required)]

        sig1 = MethodSignature.new(params: params1, return_type: "User")
        sig2 = MethodSignature.new(params: params2, return_type: "User")
        sig3 = MethodSignature.new(params: params3, return_type: "User")

        assert_equal sig1, sig2
        refute_equal sig1, sig3
      end
    end
  end
end
