# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module TypeGuessr
    class TestASTVisitor < Minitest::Test
      def setup
        @index = VariableIndex.instance
        @index.clear
      end

      def test_top_level_variable_method_calls
        source = <<~RUBY
          user = get_user
          user.name
          user.email
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # user is defined at line 1, column 0 (top-level)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "(top-level)",
          var_name: "user",
          def_line: 1,
          def_column: 0
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[email name], method_names
      end

      def test_local_variable_method_calls
        source = <<~RUBY
          def foo
            user = get_user
            user.name
            user.email
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # user is defined at line 2, column 2 (in "foo" method)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "user",
          def_line: 2,
          def_column: 2
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[email name], method_names
      end

      def test_parameter_method_calls
        source = <<~RUBY
          def greet(name)
            name.upcase
            name.strip
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # name parameter is defined at line 1, column 10 (in "greet" method)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "greet",
          var_name: "name",
          def_line: 1,
          def_column: 10
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[strip upcase], method_names
      end

      def test_scoped_variables
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

        # First user at line 2 (in "foo" method)
        calls1 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "user",
          def_line: 2,
          def_column: 2
        )

        # Second user at line 6 (in "bar" method)
        calls2 = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "bar",
          var_name: "user",
          def_line: 6,
          def_column: 4
        )

        assert_equal 1, calls1.size
        assert_equal "name", calls1[0][:method]

        assert_equal 1, calls2.size
        assert_equal "email", calls2[0][:method]
      end

      def test_keyword_parameter
        source = <<~RUBY
          def greet(name:)
            name.upcase
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # name: parameter is defined at line 1, column 10
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "greet",
          var_name: "name",
          def_line: 1,
          def_column: 10
        )

        assert_equal 1, calls.size
        assert_equal "upcase", calls[0][:method]
      end

      def test_optional_parameter
        source = <<~RUBY
          def greet(name = "World")
            name.upcase
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # name parameter is defined at line 1, column 10
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "greet",
          var_name: "name",
          def_line: 1,
          def_column: 10
        )

        assert_equal 1, calls.size
        assert_equal "upcase", calls[0][:method]
      end

      def test_rest_parameter
        source = <<~RUBY
          def greet(*names)
            names.join
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # *names parameter is defined at line 1, column 10
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "greet",
          var_name: "names",
          def_line: 1,
          def_column: 10
        )

        assert_equal 1, calls.size
        assert_equal "join", calls[0][:method]
      end

      def test_block_parameter
        source = <<~RUBY
          def execute(&block)
            block.call
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # &block parameter is defined at line 1, column 12
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "execute",
          var_name: "block",
          def_line: 1,
          def_column: 12
        )

        assert_equal 1, calls.size
        assert_equal "call", calls[0][:method]
      end

      def test_keyword_rest_parameter
        source = <<~RUBY
          def greet(**options)
            options.keys
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # **options parameter is defined at line 1, column 10
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "greet",
          var_name: "options",
          def_line: 1,
          def_column: 10
        )

        assert_equal 1, calls.size
        assert_equal "keys", calls[0][:method]
      end

      def test_block_local_variables
        source = <<~RUBY
          [1, 2, 3].each do |item|
            item.to_s
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # item is defined at line 1, column 19 (in top-level block)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "(top-level)",
          var_name: "item",
          def_line: 1,
          def_column: 19
        )

        assert_equal 1, calls.size
        assert_equal "to_s", calls[0][:method]
      end

      def test_multiple_assignment
        source = <<~RUBY
          def foo
            x, y = [1, 2]
            x.to_s
            y.to_s
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # x is defined at line 2, column 2
        calls_x = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "x",
          def_line: 2,
          def_column: 2
        )

        # y is defined at line 2, column 5
        calls_y = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "foo",
          var_name: "y",
          def_line: 2,
          def_column: 5
        )

        assert_equal 1, calls_x.size
        assert_equal "to_s", calls_x[0][:method]

        assert_equal 1, calls_y.size
        assert_equal "to_s", calls_y[0][:method]
      end

      def test_class_body_scope
        source = <<~RUBY
          class Foo
            config = load_config
            config.validate
            config.apply
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # config is defined at line 2, column 2 (in Foo class body)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Foo",
          var_name: "config",
          def_line: 2,
          def_column: 2
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[apply validate], method_names
      end

      def test_module_body_scope
        source = <<~RUBY
          module Bar
            settings = load_settings
            settings.merge
            settings.freeze
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # settings is defined at line 2, column 2 (in Bar module body)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :local_variables,
          scope_id: "Bar",
          var_name: "settings",
          def_line: 2,
          def_column: 2
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[freeze merge], method_names
      end

      def test_instance_variable_method_calls
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

        # @name is defined at line 3, column 4 (in User class)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "User",
          var_name: "@name",
          def_line: 3,
          def_column: 4
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[strip upcase], method_names
      end

      def test_class_variable_method_calls
        source = <<~RUBY
          class Config
            @@settings = load_settings
            @@settings.validate
            @@settings.freeze
          end
        RUBY

        parse_and_visit(source, "/test/file.rb")

        # @@settings is defined at line 2, column 2 (in Config class)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :class_variables,
          scope_id: "Config",
          var_name: "@@settings",
          def_line: 2,
          def_column: 2
        )

        assert_equal 2, calls.size
        method_names = calls.map { |c| c[:method] }.sort
        assert_equal %w[freeze validate], method_names
      end

      def test_instance_variable_across_methods
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

        # @var is defined at line 3, column 4 (in Hoge class)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :instance_variables,
          scope_id: "Hoge",
          var_name: "@var",
          def_line: 3,
          def_column: 4
        )

        # Should include hogehoge from line 10, and += operator from line 4
        assert_operator calls.size, :>=, 1
        method_names = calls.map { |c| c[:method] }
        assert_includes method_names, "hogehoge"
      end

      def test_class_variable_across_methods
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

        # @@count is defined at line 3, column 4 (in Config class)
        calls = @index.get_method_calls(
          file_path: "/test/file.rb",
          scope_type: :class_variables,
          scope_id: "Config",
          var_name: "@@count",
          def_line: 3,
          def_column: 4
        )

        # Should include to_s from line 11, and += operator from line 7
        assert_operator calls.size, :>=, 1
        method_names = calls.map { |c| c[:method] }
        assert_includes method_names, "to_s"
      end

      private

      def parse_and_visit(source, file_path)
        result = Prism.parse(source)
        visitor = ASTVisitor.new(file_path)
        result.value.accept(visitor)
      end
    end
  end
end
