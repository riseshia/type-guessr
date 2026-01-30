# frozen_string_literal: true

# IMPORTANT: This spec intentionally requires spec_helper but uses subprocess
# to test truly independent addon loading.
# This catches missing require_relative statements that would otherwise be
# masked by spec_helper loading type-guessr.rb first.

require "spec_helper"
require "open3"

RSpec.describe "Independent Addon Loading" do
  it "loads addon without type-guessr.rb (simulates Ruby LSP auto-discovery)" do
    # Use subprocess to ensure clean Ruby state without type-guessr.rb preloaded
    # This simulates exactly how Ruby LSP discovers and loads addons
    script = <<~RUBY
      $LOAD_PATH.unshift "#{File.expand_path("../../lib", __dir__)}"
      require "ruby_lsp/type_guessr/addon"
    RUBY

    output, status = Open3.capture2e(RbConfig.ruby, "-e", script)

    expect(status.success?).to be(true),
                               "Addon failed to load independently. This usually means a require_relative is missing.\n" \
                               "Error output:\n#{output}"
  end
end
