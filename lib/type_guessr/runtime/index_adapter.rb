# frozen_string_literal: true

require_relative "client"

module TypeGuessr
  module Runtime
    # Drop-in replacement for CodeIndexAdapter backed by Runtime::Client.
    #
    # Implements the same interface consumed by Core layer components:
    #   - find_classes_defining_methods (Resolver)
    #   - ancestors_of (MethodRegistry, SignatureRegistry, InstanceVariableRegistry, TypeSimplifier)
    #   - constant_kind, class_method_owner, instance_method_owner (RuntimeAdapter)
    #   - register_method_class, unregister_method_classes (DSL adapters)
    #
    # Unlike CodeIndexAdapter which wraps RubyIndexer (static analysis),
    # this adapter queries a live Ruby VM via subprocess IPC.
    class IndexAdapter
      def initialize(client)
        @client = client
        @extra_method_classes = Hash.new { |h, k| h[k] = Set.new }
      end

      # No-op — runtime index is built during server startup.
      def build_member_index!; end

      # No-op — runtime index doesn't support incremental refresh.
      def refresh_member_index!(_file_uri = nil); end

      # No-op — not applicable for runtime index.
      def member_entries_for_file(_file_path)
        []
      end

      # Find classes that define ALL given methods (intersection).
      # @param called_methods [Array<#name, #positional_count>] Methods to search
      # @return [Array<String>] Class names defining all methods
      def find_classes_defining_methods(called_methods)
        return [] if called_methods.empty?

        method_names = called_methods.map { |cm| cm.name.to_s }
        response = @client.find_classes(method_names)

        return [] if response["filtered"] == "all_object_methods"

        result = response["result"] || []

        # Merge with DSL-registered methods
        unless @extra_method_classes.empty?
          extra_candidates = method_names.map { |mn| @extra_method_classes[mn] }
          unless extra_candidates.any?(&:empty?)
            extra_result = extra_candidates.reduce(:&).to_a
            result = (result + extra_result).uniq
          end
        end

        result
      end

      # Get linearized ancestor chain for a class.
      # @param class_name [String] Fully qualified class name
      # @return [Array<String>] Ancestor names in MRO order
      def ancestors_of(class_name)
        @client.ancestors_of(class_name)
      end

      # Get kind of a constant.
      # @param constant_name [String]
      # @return [Symbol, nil] :class, :module, or nil
      def constant_kind(constant_name)
        result = @client.constant_kind(constant_name)
        result&.to_sym
      end

      # Look up owner of a class method.
      # @param class_name [String]
      # @param method_name [String]
      # @return [String, nil]
      def class_method_owner(class_name, method_name)
        @client.class_method_owner(class_name, method_name)
      end

      # Look up owner of an instance method.
      # @param class_name [String]
      # @param method_name [String]
      # @return [String, nil]
      def instance_method_owner(class_name, method_name)
        @client.instance_method_owner(class_name, method_name)
      end

      # Not available in runtime mode.
      def resolve_constant_name(_short_name, _nesting)
        nil
      end

      # Not available in runtime mode.
      def method_definition_file_path(_class_name, _method_name, singleton: false) # rubocop:disable Lint/UnusedMethodArgument
        nil
      end

      # Inject a custom method into the duck-typing index.
      # Used by DSL adapters (e.g., ActiveRecord column accessors).
      def register_method_class(class_name, method_name)
        @extra_method_classes[method_name] << class_name
      end

      # Remove all entries for a class from the DSL index.
      def unregister_method_classes(class_name)
        @extra_method_classes.each_value { |set| set.delete(class_name) }
      end

      # Shut down the runtime server.
      def shutdown
        @client.shutdown
      end
    end
  end
end
