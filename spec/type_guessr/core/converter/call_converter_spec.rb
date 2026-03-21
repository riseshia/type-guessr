# frozen_string_literal: true

require "spec_helper"
require "type_guessr/core/converter/prism_converter"
require "prism"

RSpec.describe TypeGuessr::Core::Converter::PrismConverter do
  let(:converter) { described_class.new }

  describe "CalledMethod signature extraction" do
    let(:called_method_class) { TypeGuessr::Core::IR::CalledMethod }

    # Helper to extract CalledMethod from a method definition
    def extract_called_method(source, param_index: 0, method_index: 0)
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)
      param = node.params[param_index]
      param.called_methods[method_index]
    end

    describe "no arguments" do
      it "extracts name, positional_count=0, keywords=[]" do
        source = <<~RUBY
          def process(obj)
            obj.no_args_method
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:no_args_method)
        expect(cm.positional_count).to eq(0)
        expect(cm.keywords).to eq([])
      end
    end

    describe "positional arguments only" do
      it "extracts name, positional_count=3, keywords=[]" do
        source = <<~RUBY
          def process(obj)
            obj.method_with_args("a", "b", "c")
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:method_with_args)
        expect(cm.positional_count).to eq(3)
        expect(cm.keywords).to eq([])
      end
    end

    describe "keyword arguments only" do
      it "extracts name, positional_count=0, keywords=[:foo, :bar]" do
        source = <<~RUBY
          def process(obj)
            obj.method_with_kwargs(foo: 1, bar: 2)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:method_with_kwargs)
        expect(cm.positional_count).to eq(0)
        expect(cm.keywords).to contain_exactly(:foo, :bar)
      end
    end

    describe "mixed positional and keyword arguments" do
      it "extracts name, positional_count=2, keywords=[:key1, :key2]" do
        source = <<~RUBY
          def process(obj)
            obj.mixed_method("a", "b", key1: 1, key2: 2)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:mixed_method)
        expect(cm.positional_count).to eq(2)
        expect(cm.keywords).to contain_exactly(:key1, :key2)
      end
    end

    describe "splat argument (*args)" do
      it "sets positional_count=nil when only splat" do
        source = <<~RUBY
          def process(obj, args)
            obj.splatted_method(*args)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:splatted_method)
        expect(cm.positional_count).to be_nil
        expect(cm.keywords).to eq([])
      end

      it "sets positional_count=nil when positional + splat" do
        source = <<~RUBY
          def process(obj, args)
            obj.method_with_splat("prefix", *args)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:method_with_splat)
        expect(cm.positional_count).to be_nil
        expect(cm.keywords).to eq([])
      end

      it "sets positional_count=nil when splat + keywords" do
        source = <<~RUBY
          def process(obj, args)
            obj.splat_with_kwargs(*args, key: "value")
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:splat_with_kwargs)
        expect(cm.positional_count).to be_nil
        expect(cm.keywords).to eq([:key])
      end

      it "sets positional_count=nil when positional + splat + keywords" do
        source = <<~RUBY
          def process(obj, args)
            obj.complex("a", *args, key: 1, other: 2)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:complex)
        expect(cm.positional_count).to be_nil
        expect(cm.keywords).to contain_exactly(:key, :other)
      end
    end

    describe "double splat (**kwargs)" do
      it "extracts positional_count=0, keywords=[] when only double splat" do
        source = <<~RUBY
          def process(obj, opts)
            obj.double_splatted(**opts)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:double_splatted)
        expect(cm.positional_count).to eq(0)
        expect(cm.keywords).to eq([])
      end

      it "extracts positional_count=2, keywords=[:explicit] when positional + explicit keyword + double splat" do
        source = <<~RUBY
          def process(obj, opts)
            obj.mixed("a", "b", explicit: 1, **opts)
          end
        RUBY
        cm = extract_called_method(source)

        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:mixed)
        expect(cm.positional_count).to eq(2)
        expect(cm.keywords).to eq([:explicit])
      end
    end

    describe "duplicate method calls" do
      it "keeps first occurrence signature (positional_count=1)" do
        source = <<~RUBY
          def process(obj)
            obj.same_method(1)
            obj.same_method(2, 3)
          end
        RUBY
        parsed = Prism.parse(source)
        context = TypeGuessr::Core::Converter::PrismConverter::Context.new
        node = converter.convert(parsed.value.statements.body.first, context)
        param = node.params.first

        same_method_entries = param.called_methods.select { |cm| cm.name == :same_method }
        expect(same_method_entries.size).to eq(1)

        cm = same_method_entries.first
        expect(cm).to be_a(called_method_class)
        expect(cm.name).to eq(:same_method)
        expect(cm.positional_count).to eq(1)
        expect(cm.keywords).to eq([])
      end
    end
  end

  describe "method call conversion" do
    it "converts simple method call" do
      source = "foo"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:foo)
      expect(node.receiver).to be_nil
    end

    it "converts method call with receiver" do
      source = <<~RUBY
        user = nil
        user.profile
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert assignment first
      converter.convert(parsed.value.statements.body[0], context)

      # Now convert the call
      node = converter.convert(parsed.value.statements.body[1], context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:profile)
      expect(node.receiver).to be_a(TypeGuessr::Core::IR::LocalReadNode)
    end

    it "tracks method calls for duck typing" do
      source = <<~RUBY
        user = nil
        user.profile
        user.name
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new

      # Convert all statements
      parsed.value.statements.body.each do |stmt|
        converter.convert(stmt, context)
      end

      # Check that user variable has called_methods tracked
      user_var = context.lookup_variable(:user)
      expect(user_var.called_methods.map(&:name)).to contain_exactly(:profile, :name)
    end

    it "converts method call with arguments" do
      source = "foo(1, 2)"
      parsed = Prism.parse(source)
      node = converter.convert(parsed.value.statements.body.first)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:foo)
      expect(node.args.size).to eq(2)
    end
  end

  describe "block conversion" do
    it "creates block parameter slots" do
      source = "[1, 2, 3].each { |x| x }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.method).to eq(:each)
      expect(node.block_params.size).to eq(1)
      expect(node.block_params.first).to be_a(TypeGuessr::Core::IR::BlockParamSlot)
      expect(node.block_params.first.index).to eq(0)
    end

    it "registers block parameters in context" do
      source = "[1, 2, 3].map { |x| x * 2 }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      converter.convert(parsed.value.statements.body.first, context)

      # Block parameter should not be visible in outer context
      expect(context.lookup_variable(:x)).to be_nil
    end

    it "tracks method calls on block parameters" do
      source = "[1, 2, 3].each { |x| x.to_s }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node).to be_a(TypeGuessr::Core::IR::CallNode)
      expect(node.block_params.first.called_methods.map(&:name)).to include(:to_s)
    end

    it "tracks multiple method calls on block parameters" do
      source = "users.each { |user| user.name; user.email }"
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      node = converter.convert(parsed.value.statements.body.first, context)

      expect(node.block_params.first.called_methods.map(&:name)).to contain_exactly(:name, :email)
    end
  end

  describe "visibility modifier with inline def" do
    it "includes private def in ClassModuleNode methods" do
      source = <<~RUBY
        class Foo
          private def bar
            42
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      method_names = class_node.methods.grep(TypeGuessr::Core::IR::DefNode).map(&:name)
      expect(method_names).to include(:bar)
    end

    it "registers private def in method_registry" do
      source = <<~RUBY
        class Foo
          private def bar
            42
          end

          def baz
            "hello"
          end
        end
      RUBY
      parsed = Prism.parse(source)
      method_registry = TypeGuessr::Core::Registry::MethodRegistry.new
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
        file_path: "test.rb",
        location_index: TypeGuessr::Core::Index::LocationIndex.new,
        method_registry: method_registry
      )
      converter.convert(parsed.value.statements.body.first, context)

      expect(method_registry.lookup("Foo", "bar")).to be_a(TypeGuessr::Core::IR::DefNode)
      expect(method_registry.lookup("Foo", "baz")).to be_a(TypeGuessr::Core::IR::DefNode)
    end

    it "includes protected def in ClassModuleNode methods" do
      source = <<~RUBY
        class Foo
          protected def bar
            42
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      class_node = converter.convert(parsed.value.statements.body.first, context)

      method_names = class_node.methods.grep(TypeGuessr::Core::IR::DefNode).map(&:name)
      expect(method_names).to include(:bar)
    end

    it "includes module_function def in ClassModuleNode methods" do
      source = <<~RUBY
        module Config
          module_function def default_config
            {}
          end
        end
      RUBY
      parsed = Prism.parse(source)
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new
      module_node = converter.convert(parsed.value.statements.body.first, context)

      def_nodes = module_node.methods.grep(TypeGuessr::Core::IR::DefNode)
      expect(def_nodes.map(&:name)).to include(:default_config)

      def_node = def_nodes.find { |m| m.name == :default_config }
      expect(def_node.singleton).to be false
      expect(def_node.module_function).to be true
    end

    it "registers module_function def in both instance and singleton scopes" do
      source = <<~RUBY
        module Config
          module_function def default_config
            {}
          end
        end
      RUBY
      parsed = Prism.parse(source)
      method_registry = TypeGuessr::Core::Registry::MethodRegistry.new
      context = TypeGuessr::Core::Converter::PrismConverter::Context.new(
        file_path: "test.rb",
        location_index: TypeGuessr::Core::Index::LocationIndex.new,
        method_registry: method_registry
      )
      converter.convert(parsed.value.statements.body.first, context)

      # Registered as instance method
      expect(method_registry.lookup("Config", "default_config")).to be_a(TypeGuessr::Core::IR::DefNode)
      # Also registered as singleton method
      expect(method_registry.lookup("Config::<Class:Config>", "default_config")).to be_a(TypeGuessr::Core::IR::DefNode)
    end
  end
end
