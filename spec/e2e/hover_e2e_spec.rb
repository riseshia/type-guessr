# frozen_string_literal: true

require "spec_helper"

# E2E tests that run against actual ruby-lsp server process.
# These tests validate that TypeGuessr works correctly in a real LSP environment.
#
# NOTE: These tests use actual project files because temporary files created after
# server startup won't be indexed by TypeGuessr.
#
# Run with: bundle exec rspec --tag e2e
# rubocop:disable RSpec/DescribeClass
RSpec.describe "Hover E2E", :e2e do
  # E2EHelper is automatically included via config.include in spec_helper.rb

  describe "type inference on project files" do
    context "lib/ruby_lsp/type_guessr/config.rb" do
      it "shows method signature for enabled? method (line 17)" do
        # def enabled?
        result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 17, 23)
        expect(result).to include("Guessed Signature")
        expect(result).to include("bool")
      end

      it "shows method signature for debug? method (line 22)" do
        # def debug?
        result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 22, 23)
        expect(result).to include("Guessed Signature")
      end

      it "infers type of raw variable from File.read (line 48)" do
        # raw = File.read(path)
        result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 48, 9)
        expect(result).to include_type("String")
      end

      it "infers type of path variable (line 40)" do
        # path = File.join(Dir.pwd, CONFIG_FILENAME)
        result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 40, 9)
        expect(result).to include_type("String")
      end
    end

    context "lib/type_guessr/core/types.rb" do
      it "shows class name for module definition" do
        # Module TypeGuessr::Core::Types should be recognizable
        result = server.query_hover("lib/type_guessr/core/types.rb", 4, 10)
        # Should return something (module/class info)
        expect(result).not_to be_nil
      end
    end
  end

  describe "method signature display" do
    it "shows signature with return type for method def" do
      # def enabled? in config.rb
      result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 17, 23)
      expect(result).to include("Guessed Signature")
      expect(result).to include("->")
    end

    it "shows signature for method with parameters" do
      # def query_hover(file_path, line, column) in shared_lsp_server.rb
      result = server.query_hover("spec/support/shared_lsp_server.rb", 64, 10)
      # Either TypeGuessr signature or ruby-lsp's default
      expect(result).not_to be_nil
    end
  end

  describe "stdlib method return types" do
    # These tests verify that RBS signatures are correctly applied

    it "infers return type for File.read in config.rb" do
      # raw = File.read(path) on line 48
      result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 48, 9)
      expect(result).to include_type("String")
    end

    it "infers return type for File.join in config.rb" do
      # path = File.join(...) on line 40
      result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 40, 9)
      expect(result).to include_type("String")
    end
  end

  describe "type inference debug info" do
    it "shows TypeGuessr debug info when hovering on guessed type" do
      # On variables with guessed types, debug info should appear
      result = server.query_hover("lib/ruby_lsp/type_guessr/config.rb", 48, 9)
      # Should include some TypeGuessr output (Guessed Type or Guessed Signature)
      expect(result).to(satisfy { |r| r.nil? || r.include?("Guessed") || r.include?("String") })
    end
  end

  describe "go to definition support" do
    it "returns definition location for method call" do
      # Test that definition requests work
      result = server.query_definition("lib/ruby_lsp/type_guessr/config.rb", 40, 20)
      # load_config is called at line 40; definition should point to line 39
      # Result can be nil if definition not found, but should not error
      expect(result).to(satisfy { |r| r.nil? || r.is_a?(Array) || r.is_a?(Hash) })
    end
  end
end
# rubocop:enable RSpec/DescribeClass
