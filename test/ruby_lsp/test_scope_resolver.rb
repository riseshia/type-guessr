# frozen_string_literal: true

require "test_helper"

module RubyLsp
  module Guesser
    class TestScopeResolver < Minitest::Test
      def test_determine_scope_type_for_local_variables
        assert_equal :local_variables, ScopeResolver.determine_scope_type("user")
        assert_equal :local_variables, ScopeResolver.determine_scope_type("some_var")
        assert_equal :local_variables, ScopeResolver.determine_scope_type("x")
      end

      def test_determine_scope_type_for_instance_variables
        assert_equal :instance_variables, ScopeResolver.determine_scope_type("@user")
        assert_equal :instance_variables, ScopeResolver.determine_scope_type("@some_var")
      end

      def test_determine_scope_type_for_class_variables
        assert_equal :class_variables, ScopeResolver.determine_scope_type("@@user")
        assert_equal :class_variables, ScopeResolver.determine_scope_type("@@counter")
      end

      def test_generate_scope_id_for_local_variables_with_method_and_class
        scope_id = ScopeResolver.generate_scope_id(
          :local_variables,
          class_path: "User",
          method_name: "initialize"
        )
        assert_equal "User#initialize", scope_id
      end

      def test_generate_scope_id_for_local_variables_with_method_only
        scope_id = ScopeResolver.generate_scope_id(
          :local_variables,
          class_path: "",
          method_name: "process"
        )
        assert_equal "process", scope_id
      end

      def test_generate_scope_id_for_local_variables_with_nested_class
        scope_id = ScopeResolver.generate_scope_id(
          :local_variables,
          class_path: "Api::User",
          method_name: "create"
        )
        assert_equal "Api::User#create", scope_id
      end

      def test_generate_scope_id_for_instance_variables_with_class
        scope_id = ScopeResolver.generate_scope_id(
          :instance_variables,
          class_path: "User"
        )
        assert_equal "User", scope_id
      end

      def test_generate_scope_id_for_instance_variables_with_nested_class
        scope_id = ScopeResolver.generate_scope_id(
          :instance_variables,
          class_path: "Api::User"
        )
        assert_equal "Api::User", scope_id
      end

      def test_generate_scope_id_for_class_variables
        scope_id = ScopeResolver.generate_scope_id(
          :class_variables,
          class_path: "User"
        )
        assert_equal "User", scope_id
      end

      def test_generate_scope_id_for_top_level
        scope_id = ScopeResolver.generate_scope_id(
          :local_variables,
          class_path: "",
          method_name: nil
        )
        assert_equal "(top-level)", scope_id
      end

      def test_generate_scope_id_for_top_level_instance_variable
        scope_id = ScopeResolver.generate_scope_id(
          :instance_variables,
          class_path: ""
        )
        assert_equal "(top-level)", scope_id
      end
    end
  end
end
