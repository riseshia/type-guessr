# frozen_string_literal: true

require "spec_helper"

RSpec.describe TypeGuessr::Core::ASTAnalyzer do
  subject(:index) { TypeGuessr::Core::VariableIndex.instance }

  before do
    index.clear
  end

  def parse_and_visit(source, file_path)
    result = Prism.parse(source)
    visitor = described_class.new(file_path)
    result.value.accept(visitor)
  end

  describe "top-level variable method calls" do
    it "tracks method calls on top-level variables" do
      source = <<~RUBY
        user = get_user
        user.name
        user.email
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "(top-level)",
        var_name: "user",
        def_line: 1,
        def_column: 0
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[email name])
    end
  end

  describe "local variable method calls" do
    it "tracks method calls within method scope" do
      source = <<~RUBY
        def foo
          user = get_user
          user.name
          user.email
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "foo",
        var_name: "user",
        def_line: 2,
        def_column: 2
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[email name])
    end
  end

  describe "parameter method calls" do
    it "tracks method calls on required parameters" do
      source = <<~RUBY
        def greet(name)
          name.upcase
          name.strip
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "greet",
        var_name: "name",
        def_line: 1,
        def_column: 10
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[strip upcase])
    end

    it "tracks method calls on keyword parameters" do
      source = <<~RUBY
        def greet(name:)
          name.upcase
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "greet",
        var_name: "name",
        def_line: 1,
        def_column: 10
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("upcase")
    end

    it "tracks method calls on optional parameters" do
      source = <<~RUBY
        def greet(name = "World")
          name.upcase
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "greet",
        var_name: "name",
        def_line: 1,
        def_column: 10
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("upcase")
    end

    it "tracks method calls on rest parameters" do
      source = <<~RUBY
        def greet(*names)
          names.join
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "greet",
        var_name: "names",
        def_line: 1,
        def_column: 10
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("join")
    end

    it "tracks method calls on block parameters" do
      source = <<~RUBY
        def execute(&block)
          block.call
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "execute",
        var_name: "block",
        def_line: 1,
        def_column: 12
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("call")
    end

    it "tracks method calls on keyword rest parameters" do
      source = <<~RUBY
        def greet(**options)
          options.keys
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "greet",
        var_name: "options",
        def_line: 1,
        def_column: 10
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("keys")
    end
  end

  describe "scoped variables" do
    it "tracks variables in different method scopes separately" do
      source = <<~RUBY
        def foo
          user = get_user
          user.name

          def bar
            user = get_another_user
            user.email
          end
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls1 = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "foo",
        var_name: "user",
        def_line: 2,
        def_column: 2
      )

      calls2 = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "bar",
        var_name: "user",
        def_line: 6,
        def_column: 4
      )

      expect(calls1.size).to eq(1)
      expect(calls1[0][:method]).to eq("name")

      expect(calls2.size).to eq(1)
      expect(calls2[0][:method]).to eq("email")
    end
  end

  describe "block local variables" do
    it "tracks method calls on block parameters" do
      source = <<~RUBY
        [1, 2, 3].each do |item|
          item.to_s
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "(top-level)",
        var_name: "item",
        def_line: 1,
        def_column: 19
      )

      expect(calls.size).to eq(1)
      expect(calls[0][:method]).to eq("to_s")
    end
  end

  describe "multiple assignment" do
    it "tracks method calls on each assigned variable" do
      source = <<~RUBY
        def foo
          x, y = [1, 2]
          x.to_s
          y.to_s
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls_x = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "foo",
        var_name: "x",
        def_line: 2,
        def_column: 2
      )

      calls_y = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "foo",
        var_name: "y",
        def_line: 2,
        def_column: 5
      )

      expect(calls_x.size).to eq(1)
      expect(calls_x[0][:method]).to eq("to_s")

      expect(calls_y.size).to eq(1)
      expect(calls_y[0][:method]).to eq("to_s")
    end
  end

  describe "class body scope" do
    it "tracks method calls in class body" do
      source = <<~RUBY
        class Foo
          config = load_config
          config.validate
          config.apply
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Foo",
        var_name: "config",
        def_line: 2,
        def_column: 2
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[apply validate])
    end
  end

  describe "module body scope" do
    it "tracks method calls in module body" do
      source = <<~RUBY
        module Bar
          settings = load_settings
          settings.merge
          settings.freeze
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :local_variables,
        scope_id: "Bar",
        var_name: "settings",
        def_line: 2,
        def_column: 2
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[freeze merge])
    end
  end

  describe "instance variable method calls" do
    it "tracks method calls on instance variables" do
      source = <<~RUBY
        class User
          def initialize
            @name = "John"
            @name.upcase
            @name.strip
          end
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :instance_variables,
        scope_id: "User",
        var_name: "@name",
        def_line: 3,
        def_column: 4
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[strip upcase])
    end

    it "tracks method calls across methods in the same class" do
      source = <<~RUBY
        class Hoge
          def initialize
            @var = 1
            @var += 2
          end

          def some_method(a, b)
            a.call_some
            b.call_other
            @var.hogehoge
          end
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :instance_variables,
        scope_id: "Hoge",
        var_name: "@var",
        def_line: 3,
        def_column: 4
      )

      expect(calls.size).to be >= 1
      method_names = calls.map { |c| c[:method] }
      expect(method_names).to include("hogehoge")
    end
  end

  describe "class variable method calls" do
    it "tracks method calls on class variables" do
      source = <<~RUBY
        class Config
          @@settings = load_settings
          @@settings.validate
          @@settings.freeze
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :class_variables,
        scope_id: "Config",
        var_name: "@@settings",
        def_line: 2,
        def_column: 2
      )

      expect(calls.size).to eq(2)
      method_names = calls.map { |c| c[:method] }.sort
      expect(method_names).to eq(%w[freeze validate])
    end

    it "tracks method calls across methods" do
      source = <<~RUBY
        class Config
          def self.init
            @@count = 0
          end

          def self.increment
            @@count += 1
          end

          def self.total
            @@count.to_s
          end
        end
      RUBY

      parse_and_visit(source, "/test/file.rb")

      calls = index.get_method_calls(
        file_path: "/test/file.rb",
        scope_type: :class_variables,
        scope_id: "Config",
        var_name: "@@count",
        def_line: 3,
        def_column: 4
      )

      expect(calls.size).to be >= 1
      method_names = calls.map { |c| c[:method] }
      expect(method_names).to include("to_s")
    end
  end
end
