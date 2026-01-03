# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Addon Loading" do
  describe "addon dependencies" do
    it "can load addon independently" do
      # Addon should already be loaded by spec_helper, so we test that its constants are available
      expect(defined?(RubyLsp::TypeGuessr::Addon)).to be_truthy
      expect(defined?(RubyLsp::TypeGuessr::Hover)).to be_truthy
      expect(defined?(RubyLsp::TypeGuessr::ChainResolver)).to be_truthy
    end

    it "uses absolute paths for core references in ChainResolver" do
      resolver_file = File.read("lib/ruby_lsp/type_guessr/chain_resolver.rb")

      expect(resolver_file).to match(/::TypeGuessr::Core::ChainContext/)
      expect(resolver_file).to match(/::TypeGuessr::Core::ScopeResolver/)
    end

    it "explicitly requires chain_resolver in Hover" do
      hover_file = File.read("lib/ruby_lsp/type_guessr/hover.rb")

      expect(hover_file).to match(/require_relative.*chain_resolver/)
    end
  end
end
