# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module TypeGuessr
    class TestAddonLoading < Minitest::Test
      def test_addon_can_be_loaded_independently
        # This tests that addon and its dependencies can load without main entry point
        # Addon should already be loaded by test_helper, so we test that its constants are available

        # If addon loaded successfully, these constants should be defined
        assert defined?(RubyLsp::TypeGuessr::Addon), "Addon class should be defined"
        assert defined?(RubyLsp::TypeGuessr::Hover), "Hover class should be defined"
        assert defined?(RubyLsp::TypeGuessr::VariableTypeResolver), "VariableTypeResolver should be defined"
      end

      def test_variable_type_resolver_has_explicit_requires
        # VariableTypeResolver should explicitly require or reference
        # its dependencies using absolute paths
        resolver_file = File.read("lib/type_guessr/integrations/ruby_lsp/variable_type_resolver.rb")

        # Check that it uses absolute paths for core references
        assert_match(/::TypeGuessr::Core::TypeResolver/, resolver_file,
                     "VariableTypeResolver should use absolute path for TypeResolver")
        assert_match(/::TypeGuessr::Core::ScopeResolver/, resolver_file,
                     "VariableTypeResolver should use absolute path for ScopeResolver")
      end

      def test_hover_has_explicit_requires
        # HoverProvider should have explicit requires for its dependencies
        hover_file = File.read("lib/type_guessr/integrations/ruby_lsp/hover_provider.rb")

        # Check that it requires variable_type_resolver
        assert_match(/require_relative.*variable_type_resolver/, hover_file,
                     "HoverProvider should explicitly require VariableTypeResolver")
      end
    end
  end
end
