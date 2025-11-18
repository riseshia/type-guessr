# frozen_string_literal: true

# This test file intentionally does NOT require test_helper
# to simulate how Ruby LSP loads the addon independently
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "minitest/autorun"

module RubyLsp
  module TypeGuessr
    class TestIndependentAddonLoading < Minitest::Test
      def test_addon_can_load_without_main_entry_point
        # This simulates how Ruby LSP loads the addon:
        # It requires the addon file directly without going through lib/type-guessr.rb

        # If the addon doesn't have explicit requires for its core dependencies,
        # this will raise NameError: uninitialized constant

        require "ruby_lsp/type_guessr/addon"

        # Verify the addon class is defined
        assert defined?(RubyLsp::TypeGuessr::Addon), "Addon class should be defined"

        # Verify core dependencies are accessible
        assert defined?(::TypeGuessr::Core::ASTAnalyzer), "ASTAnalyzer should be loaded"
        assert defined?(::TypeGuessr::Core::RBSIndexer), "RBSIndexer should be loaded"
        assert defined?(::TypeGuessr::Core::VariableIndex), "VariableIndex should be loaded"
      end

      def test_variable_type_resolver_can_load_independently
        # Same for VariableTypeResolver
        require "ruby_lsp/type_guessr/variable_type_resolver"

        assert defined?(RubyLsp::TypeGuessr::VariableTypeResolver),
               "VariableTypeResolver should be defined"

        # Verify it can access core dependencies
        assert defined?(::TypeGuessr::Core::VariableIndex), "VariableIndex should be loaded"
        assert defined?(::TypeGuessr::Core::ScopeResolver), "ScopeResolver should be loaded"
      end

      def test_hover_can_load_independently
        # And for Hover
        require "ruby_lsp/type_guessr/hover"

        assert defined?(RubyLsp::TypeGuessr::Hover), "Hover class should be defined"
      end
    end
  end
end
