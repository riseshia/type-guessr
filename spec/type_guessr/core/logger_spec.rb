# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/logger"

RSpec.describe TypeGuessr::Core::Logger do
  # Helper to capture stderr output
  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end

  describe ".debug_enabled?" do
    it "delegates to Config.debug?" do
      allow(RubyLsp::TypeGuessr::Config).to receive(:debug?).and_return(true)
      expect(described_class.debug_enabled?).to be true

      allow(RubyLsp::TypeGuessr::Config).to receive(:debug?).and_return(false)
      expect(described_class.debug_enabled?).to be false
    end
  end

  describe ".debug" do
    context "when debug is enabled" do
      before do
        allow(described_class).to receive(:debug_enabled?).and_return(true)
      end

      it "outputs debug message to stderr" do
        output = capture_stderr do
          described_class.debug("Test message")
        end
        expect(output).to include("[TypeGuessr:DEBUG] Test message")
      end

      it "includes context when provided" do
        output = capture_stderr do
          described_class.debug("Test message", { file: "foo.rb", line: 42 })
        end
        expect(output).to include("[TypeGuessr:DEBUG] Test message")
        expect(output).to include("file")
        expect(output).to include("foo.rb")
        expect(output).to include("line")
        expect(output).to include("42")
      end

      it "handles empty context" do
        output = capture_stderr do
          described_class.debug("Test message", {})
        end
        expect(output).to eq("[TypeGuessr:DEBUG] Test message\n")
      end
    end

    context "when debug is disabled" do
      before do
        allow(described_class).to receive(:debug_enabled?).and_return(false)
      end

      it "does not output anything" do
        output = capture_stderr do
          described_class.debug("Test message")
        end
        expect(output).to be_empty
      end
    end
  end

  describe ".error" do
    context "when debug is enabled" do
      before do
        allow(described_class).to receive(:debug_enabled?).and_return(true)
      end

      it "outputs error message to stderr" do
        output = capture_stderr do
          described_class.error("Something went wrong")
        end
        expect(output).to include("[TypeGuessr:ERROR] Something went wrong")
      end

      it "includes exception details when provided" do
        exception = StandardError.new("Test error")
        exception.set_backtrace([
                                  "/path/to/file.rb:10:in `method1'",
                                  "/path/to/file.rb:20:in `method2'",
                                  "/path/to/file.rb:30:in `method3'",
                                  "/path/to/file.rb:40:in `method4'",
                                  "/path/to/file.rb:50:in `method5'",
                                  "/path/to/file.rb:60:in `method6'",
                                ])

        output = capture_stderr do
          described_class.error("Operation failed", exception)
        end

        expect(output).to include("[TypeGuessr:ERROR] Operation failed")
        expect(output).to include("StandardError: Test error")
        expect(output).to include("/path/to/file.rb:10:in `method1'")
        expect(output).to include("/path/to/file.rb:50:in `method5'")
        expect(output).not_to include("/path/to/file.rb:60:in `method6'") # Only first 5 lines
      end

      it "handles error without exception" do
        output = capture_stderr do
          described_class.error("Generic error")
        end
        expect(output).to eq("[TypeGuessr:ERROR] Generic error\n")
      end
    end

    context "when debug is disabled" do
      before do
        allow(described_class).to receive(:debug_enabled?).and_return(false)
      end

      it "does not output anything" do
        exception = StandardError.new("Test error")
        output = capture_stderr do
          described_class.error("Something went wrong", exception)
        end
        expect(output).to be_empty
      end
    end
  end
end
