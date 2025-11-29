# frozen_string_literal: true

# This spec file intentionally does NOT require spec_helper
# to simulate how Ruby LSP loads the addon independently
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

RSpec.describe "Independent Addon Loading", skip: "Already tested in addon_loading_spec" do
  it "can load addon without main entry point" do
    # This simulates how Ruby LSP loads the addon:
    # It requires the addon file directly without going through lib/type-guessr.rb
    require "ruby_lsp/type_guessr/addon"

    expect(defined?(RubyLsp::TypeGuessr::Addon)).to be_truthy
    expect(defined?(TypeGuessr::Core::ASTAnalyzer)).to be_truthy
    expect(defined?(TypeGuessr::Core::VariableIndex)).to be_truthy
  end

  it "can load variable_type_resolver independently" do
    require "ruby_lsp/type_guessr/variable_type_resolver"

    expect(defined?(RubyLsp::TypeGuessr::VariableTypeResolver)).to be_truthy
    expect(defined?(TypeGuessr::Core::VariableIndex)).to be_truthy
    expect(defined?(TypeGuessr::Core::ScopeResolver)).to be_truthy
  end

  it "can load hover independently" do
    require "ruby_lsp/type_guessr/hover"

    expect(defined?(RubyLsp::TypeGuessr::Hover)).to be_truthy
  end
end
