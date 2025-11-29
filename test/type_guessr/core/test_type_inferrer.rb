# frozen_string_literal: true

require "test_helper"

module TypeGuessr
  module Core
    class TestTypeInferrer < Minitest::Test
      def setup
        @index = RubyIndexer::Index.new
        @inferrer = TypeInferrer.new(@index)
      end

      def test_inherits_from_ruby_lsp_type_inferrer
        assert_kind_of ::RubyLsp::TypeInferrer, @inferrer
      end

      def test_type_class_stores_name
        type = ::RubyLsp::TypeInferrer::Type.new("String")
        assert_equal "String", type.name
      end

      def test_type_attached_removes_singleton_class
        type = ::RubyLsp::TypeInferrer::Type.new("Foo::Bar::<Class:Bar>")
        attached = type.attached
        assert_equal "Foo::Bar", attached.name
      end

      def test_guessed_type_inherits_from_type
        guessed = ::RubyLsp::TypeInferrer::GuessedType.new("User")
        assert_kind_of ::RubyLsp::TypeInferrer::Type, guessed
        assert_equal "User", guessed.name
      end
    end
  end
end
