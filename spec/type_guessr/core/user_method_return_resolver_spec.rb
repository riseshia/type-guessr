# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "type_guessr/core/user_method_return_resolver"
require "type_guessr/core/types"

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles, RSpec/ContextWording
RSpec.describe TypeGuessr::Core::UserMethodReturnResolver do
  let(:index_adapter) { double("IndexAdapter") }
  let(:resolver) { described_class.new(index_adapter) }
  let(:nil_class_type) { TypeGuessr::Core::Types::ClassInstance.new("NilClass") }
  let(:string_type) { TypeGuessr::Core::Types::ClassInstance.new("String") }
  let(:integer_type) { TypeGuessr::Core::Types::ClassInstance.new("Integer") }
  let(:unknown_type) { TypeGuessr::Core::Types::Unknown.instance }

  describe "#get_return_type" do
    context "when method has empty body" do
      it "returns NilClass" do
        source = <<~RUBY
          def eat
          end
        RUBY

        entry = create_method_entry("eat", source)
        allow(index_adapter).to receive(:resolve_method).with("eat", "Animal").and_return([entry])

        result = resolver.get_return_type("Animal", "eat")

        expect(result).to eq(nil_class_type)
      end
    end

    context "when method has literal return value" do
      it "returns String for string literal" do
        source = <<~RUBY
          def name
            "Alice"
          end
        RUBY

        entry = create_method_entry("name", source)
        allow(index_adapter).to receive(:resolve_method).with("name", "User").and_return([entry])

        result = resolver.get_return_type("User", "name")

        expect(result).to eq(string_type)
      end

      it "returns Integer for integer literal" do
        source = <<~RUBY
          def age
            30
          end
        RUBY

        entry = create_method_entry("age", source)
        allow(index_adapter).to receive(:resolve_method).with("age", "User").and_return([entry])

        result = resolver.get_return_type("User", "age")

        expect(result).to eq(integer_type)
      end
    end

    context "when method has explicit return statement" do
      it "infers type from return value" do
        source = <<~RUBY
          def greet
            return "Hello"
          end
        RUBY

        entry = create_method_entry("greet", source)
        allow(index_adapter).to receive(:resolve_method).with("greet", "Greeter").and_return([entry])

        result = resolver.get_return_type("Greeter", "greet")

        expect(result).to eq(string_type)
      end
    end

    context "when method is not found" do
      it "returns Unknown" do
        allow(index_adapter).to receive(:resolve_method).with("missing", "Foo").and_return(nil)

        result = resolver.get_return_type("Foo", "missing")

        expect(result).to eq(unknown_type)
      end

      it "returns Unknown when entries array is empty" do
        allow(index_adapter).to receive(:resolve_method).with("missing", "Foo").and_return([])

        result = resolver.get_return_type("Foo", "missing")

        expect(result).to eq(unknown_type)
      end
    end

    context "when file cannot be read" do
      it "returns Unknown" do
        entry = create_method_entry("foo", "def foo; end", file_path: "/nonexistent/file.rb")
        allow(index_adapter).to receive(:resolve_method).with("foo", "Bar").and_return([entry])

        result = resolver.get_return_type("Bar", "foo")

        expect(result).to eq(unknown_type)
      end
    end

    context "caching behavior" do
      it "caches results to avoid repeated analysis" do
        source = <<~RUBY
          def cached_method
            "cached"
          end
        RUBY

        entry = create_method_entry("cached_method", source)
        allow(index_adapter).to receive(:resolve_method).with("cached_method", "Test").and_return([entry])

        # First call
        result1 = resolver.get_return_type("Test", "cached_method")
        # Second call
        result2 = resolver.get_return_type("Test", "cached_method")

        expect(result1).to eq(string_type)
        expect(result2).to eq(string_type)
        # Verify index_adapter was called only once
        expect(index_adapter).to have_received(:resolve_method).once
      end
    end

    context "depth limit" do
      it "returns Unknown when max depth is exceeded" do
        source = <<~RUBY
          def recursive
            "result"
          end
        RUBY

        entry = create_method_entry("recursive", source)
        allow(index_adapter).to receive(:resolve_method).with("recursive", "Test").and_return([entry])

        result = resolver.get_return_type("Test", "recursive", depth: 10)

        expect(result).to eq(unknown_type)
      end
    end
  end

  # Helper method to create a mock method entry
  def create_method_entry(_method_name, source, file_path: nil)
    # Create a temporary file with the source
    file_path ||= begin
      file = Tempfile.new(["method_test", ".rb"])
      file.write(source)
      file.close
      file.path
    end

    # Parse to get line info
    lines = source.lines.count

    # Create mock entry
    location = double("Location",
                      start_line: 1,
                      end_line: lines,
                      start_column: 0,
                      end_column: 0)

    uri = double("URI", to_s: "file://#{file_path}")

    double("Entry",
           uri: uri,
           location: location)
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/VerifiedDoubles, RSpec/ContextWording
