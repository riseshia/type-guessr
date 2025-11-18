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

        require "type_guessr/integrations/ruby_lsp/addon"

        # Verify the addon class is defined in new namespace
        assert defined?(::TypeGuessr::Integrations::RubyLsp::Addon), "Addon class should be defined in new namespace"

        # Verify core dependencies are accessible
        assert defined?(::TypeGuessr::Core::ASTAnalyzer), "ASTAnalyzer should be loaded"
        assert defined?(::TypeGuessr::Core::RBSIndexer), "RBSIndexer should be loaded"
        assert defined?(::TypeGuessr::Core::VariableIndex), "VariableIndex should be loaded"
      end

      def test_variable_type_resolver_can_load_independently
        # Same for VariableTypeResolver
        require "type_guessr/integrations/ruby_lsp/variable_type_resolver"

        assert defined?(::TypeGuessr::Integrations::RubyLsp::VariableTypeResolver),
               "VariableTypeResolver should be defined in new namespace"

        # Verify it can access core dependencies
        assert defined?(::TypeGuessr::Core::VariableIndex), "VariableIndex should be loaded"
        assert defined?(::TypeGuessr::Core::ScopeResolver), "ScopeResolver should be loaded"
      end

      def test_hover_can_load_independently
        # And for HoverProvider
        require "type_guessr/integrations/ruby_lsp/hover_provider"

        assert defined?(::TypeGuessr::Integrations::RubyLsp::HoverProvider),
               "HoverProvider class should be defined in new namespace"
      end
    end
  end
end
