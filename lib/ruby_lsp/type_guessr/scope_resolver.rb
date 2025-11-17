# frozen_string_literal: true

module RubyLsp
  module TypeGuessr
    # Provides common scope resolution logic for determining scope types and IDs
    # Used by both ASTVisitor and Hover to maintain consistency
    module ScopeResolver
      # Determine the scope type based on variable name
      # @param var_name [String] the variable name
      # @return [Symbol] :class_variables, :instance_variables, or :local_variables
      def self.determine_scope_type(var_name)
        if var_name.start_with?("@@")
          :class_variables
        elsif var_name.start_with?("@")
          :instance_variables
        else
          :local_variables
        end
      end

      # Generate scope ID for the current context
      # - For instance/class variables: "ClassName" or "Module::ClassName"
      # - For local variables: "ClassName#method_name"
      # - For top-level: "(top-level)"
      #
      # @param scope_type [Symbol] the scope type (:local_variables, :instance_variables, :class_variables)
      # @param class_path [String] the class path (e.g., "User", "Api::User")
      # @param method_name [String, nil] the method name (optional, used for local variables)
      # @return [String] the scope ID
      def self.generate_scope_id(scope_type, class_path: "", method_name: nil)
        if scope_type == :local_variables && method_name && !method_name.empty?
          # Local variable: "ClassName#method_name"
          class_path.empty? ? method_name : "#{class_path}##{method_name}"
        elsif !class_path.empty?
          # Instance/class variable: "ClassName"
          class_path
        else
          # Top-level scope
          "(top-level)"
        end
      end
    end
  end
end
