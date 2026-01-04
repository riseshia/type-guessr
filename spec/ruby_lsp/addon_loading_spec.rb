# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Addon Loading" do
  describe "addon dependencies" do
    it "can load addon independently" do
      # Verify addon can be required without errors
      expect do
        require_relative "../../lib/ruby_lsp/type_guessr/addon"
      end.not_to raise_error
    end

    it "uses IR-based architecture" do
      addon_file = File.read("lib/ruby_lsp/type_guessr/addon.rb")

      # Check for new IR-based dependencies
      expect(addon_file).to match(/require_relative.*runtime_adapter/)
      expect(addon_file).to match(/RuntimeAdapter/)
    end

    it "Hover uses IR-based inference" do
      hover_file = File.read("lib/ruby_lsp/type_guessr/hover.rb")

      # Check for IR-based inference
      expect(hover_file).to match(/find_node_at/)
      expect(hover_file).to match(/infer_type/)
    end
  end
end
