# frozen_string_literal: true

require "test_helper"

module RubyLsp
  class TestGuesser < Minitest::Test
    def test_that_it_has_a_version_number
      refute_nil ::RubyLsp::TypeGuessr::VERSION
    end

    def test_addon_name
      addon = TypeGuessr::Addon.new
      assert_equal "TypeGuessr", addon.name
    end

    def test_hover_class_exists
      assert defined?(RubyLsp::TypeGuessr::Hover)
    end
  end
end
