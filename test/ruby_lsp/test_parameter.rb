# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module TypeGuessr
    class TestParameter < Minitest::Test
      def test_positional_parameter
        param = Parameter.new(name: "id", type: "Integer", kind: :required)

        assert_equal "id", param.name
        assert_equal "Integer", param.type
        assert_equal :required, param.kind
        assert param.positional?
        refute param.keyword?
        refute param.block?
        assert param.required?
      end

      def test_optional_parameter
        param = Parameter.new(name: "name", type: "String", kind: :optional)

        assert param.positional?
        refute param.required?
      end

      def test_keyword_parameter
        param = Parameter.new(name: "age", type: "Integer", kind: :keyword)

        assert param.keyword?
        refute param.positional?
        assert param.required?
      end

      def test_block_parameter
        param = Parameter.new(name: "block", type: "Proc", kind: :block, required: true)

        assert param.block?
        refute param.positional?
        refute param.keyword?
        assert param.required?
      end

      def test_optional_block_parameter
        param = Parameter.new(name: "block", type: "Proc", kind: :block, required: false)

        assert param.block?
        refute param.required?
      end

      def test_to_s_required
        param = Parameter.new(name: "id", type: "Integer", kind: :required)
        assert_equal "Integer id", param.to_s
      end

      def test_to_s_optional
        param = Parameter.new(name: "name", type: "String", kind: :optional)
        assert_equal "?String name", param.to_s
      end

      def test_to_s_rest
        param = Parameter.new(name: "args", type: "Integer", kind: :rest)
        assert_equal "*Integer args", param.to_s
      end

      def test_to_s_keyword
        param = Parameter.new(name: "age", type: "Integer", kind: :keyword)
        assert_equal "age: Integer", param.to_s
      end

      def test_equality
        param1 = Parameter.new(name: "id", type: "Integer", kind: :required)
        param2 = Parameter.new(name: "id", type: "Integer", kind: :required)
        param3 = Parameter.new(name: "id", type: "String", kind: :required)

        assert_equal param1, param2
        refute_equal param1, param3
      end

      def test_hash
        param1 = Parameter.new(name: "id", type: "Integer", kind: :required)
        param2 = Parameter.new(name: "id", type: "Integer", kind: :required)

        hash = { param1 => "value" }
        assert_equal "value", hash[param2]
      end
    end
  end
end
