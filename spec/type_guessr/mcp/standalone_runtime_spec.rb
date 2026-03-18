# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"
require "type_guessr/mcp/standalone_runtime"
require "tempfile"

RSpec.describe TypeGuessr::MCP::StandaloneRuntime do
  include TypeGuessrTestHelper

  # Build a StandaloneRuntime by indexing source through the full pipeline.
  # Writes source to a temp file so that #infer_at can read it back.
  # Yields runtime, file_path, and signature_registry to avoid singleton dependency.
  def build_runtime_with_source(source)
    with_server_and_addon(source) do |server, _uri|
      code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(server.global_state.index)
      # Build own preloaded registry to avoid singleton pollution from test ordering
      signature_registry = TypeGuessr::Core::Registry::SignatureRegistry.new(code_index: code_index)
      signature_registry.preload

      method_registry = TypeGuessr::Core::Registry::MethodRegistry.new(code_index: code_index)
      ivar_registry = TypeGuessr::Core::Registry::InstanceVariableRegistry.new(code_index: code_index)
      cvar_registry = TypeGuessr::Core::Registry::ClassVariableRegistry.new
      type_simplifier = TypeGuessr::Core::TypeSimplifier.new(code_index: code_index)

      resolver = TypeGuessr::Core::Inference::Resolver.new(
        signature_registry,
        code_index: code_index,
        method_registry: method_registry,
        ivar_registry: ivar_registry,
        cvar_registry: cvar_registry,
        type_simplifier: type_simplifier
      )

      runtime = described_class.new(
        converter: TypeGuessr::Core::Converter::PrismConverter.new,
        location_index: TypeGuessr::Core::Index::LocationIndex.new,
        signature_registry: signature_registry,
        method_registry: method_registry,
        ivar_registry: ivar_registry,
        cvar_registry: cvar_registry,
        resolver: resolver,
        signature_builder: TypeGuessr::Core::SignatureBuilder.new(resolver),
        code_index: code_index
      )

      # Write source to a temp file so infer_at can File.read it
      Tempfile.create(["source", ".rb"]) do |tmpfile|
        tmpfile.write(source)
        tmpfile.flush
        file_path = tmpfile.path

        parsed = Prism.parse(source)
        runtime.index_parsed_file(file_path, parsed)
        runtime.finalize_index!

        yield runtime, file_path, signature_registry
      end
    end
  end

  describe "#method_signature" do
    it "returns project method signature" do
      source = <<~RUBY
        class User
          def save(validate: true)
            validate
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        result = runtime.method_signature("User", "save")

        expect(result[:source]).to eq("project")
        expect(result[:signature]).to be_a(String)
        expect(result[:class_name]).to eq("User")
        expect(result[:method_name]).to eq("save")
      end
    end

    it "falls back to RBS for stdlib methods" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        result = runtime.method_signature("String", "size")

        expect(result[:source]).to eq("rbs")
        expect(result[:signatures]).to be_an(Array)
        expect(result[:signatures]).not_to be_empty
        expect(result[:class_name]).to eq("String")
        expect(result[:method_name]).to eq("size")
      end
    end

    it "returns gem cache method signature" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, registry|
        # Register a gem method on the runtime's own registry
        return_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        params = [
          TypeGuessr::Core::Types::ParamSignature.new(
            name: :key, kind: :required, type: TypeGuessr::Core::Types::ClassInstance.new("Symbol")
          ),
        ]
        registry.register_gem_method("MyGem::Config", "fetch", return_type, params)

        result = runtime.method_signature("MyGem::Config", "fetch")

        expect(result).not_to have_key(:error)
        expect(result[:source]).to eq("gem_cache")
        expect(result[:signatures]).to include("(Symbol key) -> String")
      end
    end

    it "returns error for unknown method" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        result = runtime.method_signature("NonExistentClass", "unknown_method")

        expect(result).to have_key(:error)
        expect(result[:error]).to include("Method not found")
        expect(result[:class_name]).to eq("NonExistentClass")
        expect(result[:method_name]).to eq("unknown_method")
      end
    end
  end

  describe "#search_methods" do
    it "finds methods by name" do
      source = <<~RUBY
        class Animal
          def speak
            "..."
          end
        end

        class Dog < Animal
          def speak
            "woof"
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.search_methods("speak")

        expect(results).to be_an(Array)
        expect(results.length).to be >= 2

        full_names = results.map { |r| r[:full_name] }
        expect(full_names).to include("Animal#speak")
        expect(full_names).to include("Dog#speak")
      end
    end

    it "finds methods by class#method pattern" do
      source = <<~RUBY
        class Foo
          def bar; end
          def baz; end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.search_methods("Foo#bar")

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results.first[:full_name]).to eq("Foo#bar")
      end
    end

    it "returns empty array for no matches" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.search_methods("zzz_nonexistent_method_zzz")

        expect(results).to eq([])
      end
    end

    it "includes signatures when include_signatures is true" do
      source = <<~RUBY
        class Calculator
          def add(a, b)
            a + b
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.search_methods("Calculator#add", include_signatures: true)

        expect(results.length).to eq(1)
        result = results.first
        expect(result[:signature]).to be_a(String)
        expect(result[:signature]).to include("a")
        expect(result[:signature]).to include("b")
      end
    end

    it "does not include signatures by default" do
      source = <<~RUBY
        class Greeter
          def hello; end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.search_methods("Greeter#hello")

        expect(results.first).not_to have_key(:signature)
      end
    end
  end

  describe "#method_signatures" do
    it "returns signatures for multiple methods in one call" do
      source = <<~RUBY
        class Order
          def cancel; end
          def save; end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.method_signatures([
                                              { class_name: "Order", method_name: "cancel" },
                                              { class_name: "Order", method_name: "save" },
                                            ])

        expect(results).to be_an(Array)
        expect(results.length).to eq(2)
        expect(results[0][:class_name]).to eq("Order")
        expect(results[0][:method_name]).to eq("cancel")
        expect(results[0][:source]).to eq("project")
        expect(results[1][:class_name]).to eq("Order")
        expect(results[1][:method_name]).to eq("save")
      end
    end

    it "returns error entry for missing methods without affecting others" do
      source = <<~RUBY
        class Order
          def cancel; end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.method_signatures([
                                              { class_name: "Order", method_name: "cancel" },
                                              { class_name: "Order", method_name: "nonexistent" },
                                            ])

        expect(results.length).to eq(2)
        expect(results[0][:source]).to eq("project")
        expect(results[1]).to have_key(:error)
        expect(results[1][:class_name]).to eq("Order")
        expect(results[1][:method_name]).to eq("nonexistent")
      end
    end

    it "returns empty array for empty input" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.method_signatures([])

        expect(results).to eq([])
      end
    end
  end

  describe "#method_sources" do
    it "returns source code for methods" do
      source = <<~RUBY
        class Order
          def cancel
            @cancelled = true
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path, _registry|
        results = runtime.method_sources([
                                           { class_name: "Order", method_name: "cancel" },
                                         ])

        expect(results.length).to eq(1)
        result = results.first
        expect(result[:class_name]).to eq("Order")
        expect(result[:method_name]).to eq("cancel")
        expect(result[:source]).to include("def cancel")
        expect(result[:source]).to include("@cancelled = true")
        expect(result[:file_path]).to eq(file_path)
        expect(result[:line]).to be_a(Integer)
      end
    end

    it "returns error for unknown method" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.method_sources([
                                           { class_name: "Order", method_name: "nonexistent" },
                                         ])

        expect(results.length).to eq(1)
        expect(results.first).to have_key(:error)
        expect(results.first[:class_name]).to eq("Order")
        expect(results.first[:method_name]).to eq("nonexistent")
      end
    end

    it "returns empty array for empty input" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        results = runtime.method_sources([])
        expect(results).to eq([])
      end
    end
  end

  describe "#index_parsed_file" do
    it "skips files with parse errors gracefully" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path, _registry|
        bad_result = Prism.parse("def foo(")

        # Should not raise
        expect { runtime.index_parsed_file("/tmp/bad.rb", bad_result) }.not_to raise_error
      end
    end

    it "reflects updated methods after re-indexing a modified file" do
      source = <<~RUBY
        class Updater
          def value; end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path, _registry|
        results = runtime.search_methods("Updater#value")
        expect(results.length).to eq(1)

        # Modify the file: rename method
        new_source = <<~RUBY
          class Updater
            def new_value; end
          end
        RUBY
        File.write(file_path, new_source)

        # Re-index
        parsed = Prism.parse(new_source)
        runtime.index_parsed_file(file_path, parsed)

        expect(runtime.search_methods("Updater#value")).to be_empty
        expect(runtime.search_methods("Updater#new_value").length).to eq(1)
      end
    end
  end

  describe "#remove_indexed_file" do
    it "removes indexed methods so search returns empty" do
      source = <<~RUBY
        class Removable
          def greet
            name = "hello"
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path, _registry|
        # Verify method is searchable before removal
        expect(runtime.search_methods("Removable#greet").length).to eq(1)

        # Remove the file from index
        runtime.remove_indexed_file(file_path)

        # Now search should return empty
        expect(runtime.search_methods("Removable#greet")).to be_empty
      end
    end
  end
end
