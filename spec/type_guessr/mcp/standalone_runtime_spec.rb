# frozen_string_literal: true

require "spec_helper"
require "ruby_lsp/internal"
require "type_guessr/mcp/standalone_runtime"
require "tempfile"

RSpec.describe TypeGuessr::MCP::StandaloneRuntime do
  include TypeGuessrTestHelper

  # Build a StandaloneRuntime by indexing source through the full pipeline.
  # Writes source to a temp file so that #infer_at can read it back.
  def build_runtime_with_source(source)
    with_server_and_addon(source) do |server, _uri|
      code_index = RubyLsp::TypeGuessr::CodeIndexAdapter.new(server.global_state.index)
      signature_registry = TypeGuessr::Core::Registry::SignatureRegistry.instance

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

        yield runtime, file_path
      end
    end
  end

  describe "#infer_at" do
    it "infers type for a string literal" do
      source = <<~RUBY
        class Greeter
          def greet
            name = "hello"
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path|
        # line 3, column 4 → `name` (local variable assigned to string)
        result = runtime.infer_at(file_path, 3, 4)

        expect(result).not_to have_key(:error)
        expect(result[:type]).to include("String")
      end
    end

    it "infers method signature for a def node" do
      source = <<~RUBY
        class Calculator
          def add(a, b)
            a + b
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path|
        # line 2, column 6 → `add` (def node)
        result = runtime.infer_at(file_path, 2, 6)

        expect(result).not_to have_key(:error)
        expect(result[:node_type]).to eq("DefNode")
        expect(result[:type]).to eq("method_signature")
      end
    end

    it "returns error for invalid position" do
      source = <<~RUBY
        x = 1
      RUBY

      build_runtime_with_source(source) do |runtime, file_path|
        result = runtime.infer_at(file_path, 999, 0)

        expect(result).to have_key(:error)
      end
    end

    it "returns error for non-existent file" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        result = runtime.infer_at("/nonexistent/file.rb", 1, 0)

        expect(result).to have_key(:error)
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

      build_runtime_with_source(source) do |runtime, _file_path|
        result = runtime.method_signature("User", "save")

        expect(result[:source]).to eq("project")
        expect(result[:signature]).to be_a(String)
        expect(result[:class_name]).to eq("User")
        expect(result[:method_name]).to eq("save")
      end
    end

    it "falls back to RBS for stdlib methods" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        result = runtime.method_signature("String", "size")

        expect(result[:source]).to eq("rbs")
        expect(result[:signatures]).to be_an(Array)
        expect(result[:signatures]).not_to be_empty
      end
    end

    it "returns gem cache method signature" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        # Register a gem method directly
        return_type = TypeGuessr::Core::Types::ClassInstance.new("String")
        params = [
          TypeGuessr::Core::Types::ParamSignature.new(
            name: :key, kind: :required, type: TypeGuessr::Core::Types::ClassInstance.new("Symbol")
          ),
        ]
        registry = TypeGuessr::Core::Registry::SignatureRegistry.instance
        registry.register_gem_method("MyGem::Config", "fetch", return_type, params)

        result = runtime.method_signature("MyGem::Config", "fetch")

        expect(result).not_to have_key(:error)
        expect(result[:source]).to eq("gem_cache")
        expect(result[:signatures]).to include("(Symbol key) -> String")
      end
    end

    it "returns error for unknown method" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        result = runtime.method_signature("NonExistentClass", "unknown_method")

        expect(result).to have_key(:error)
        expect(result[:error]).to include("Method not found")
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

      build_runtime_with_source(source) do |runtime, _file_path|
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

      build_runtime_with_source(source) do |runtime, _file_path|
        results = runtime.search_methods("Foo#bar")

        expect(results).to be_an(Array)
        expect(results.length).to eq(1)
        expect(results.first[:full_name]).to eq("Foo#bar")
      end
    end

    it "returns empty array for no matches" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        results = runtime.search_methods("zzz_nonexistent_method_zzz")

        expect(results).to eq([])
      end
    end
  end

  describe "#index_parsed_file" do
    it "skips files with parse errors gracefully" do
      source = "x = 1"

      build_runtime_with_source(source) do |runtime, _file_path|
        bad_result = Prism.parse("def foo(")

        # Should not raise
        expect { runtime.index_parsed_file("/tmp/bad.rb", bad_result) }.not_to raise_error
      end
    end

    it "reflects updated type after re-indexing a modified file" do
      source = <<~RUBY
        class Updater
          def value
            x = "hello"
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path|
        result = runtime.infer_at(file_path, 3, 4)
        expect(result[:type]).to include("String")

        # Modify the file: change string to integer
        new_source = <<~RUBY
          class Updater
            def value
              x = 42
            end
          end
        RUBY
        File.write(file_path, new_source)

        # Re-index
        parsed = Prism.parse(new_source)
        runtime.index_parsed_file(file_path, parsed)

        result = runtime.infer_at(file_path, 3, 4)
        expect(result[:type]).to include("Integer")
      end
    end
  end

  describe "#remove_indexed_file" do
    it "removes indexed nodes so queries return error" do
      source = <<~RUBY
        class Removable
          def greet
            name = "hello"
          end
        end
      RUBY

      build_runtime_with_source(source) do |runtime, file_path|
        # Verify it works before removal
        result = runtime.infer_at(file_path, 3, 4)
        expect(result).not_to have_key(:error)

        # Remove the file from index
        runtime.remove_indexed_file(file_path)

        # Now queries should return error (node not indexed)
        result = runtime.infer_at(file_path, 3, 4)
        expect(result).to have_key(:error)
      end
    end
  end
end
