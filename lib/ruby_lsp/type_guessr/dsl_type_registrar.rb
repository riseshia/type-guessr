# frozen_string_literal: true

require_relative "dsl"

module RubyLsp
  module TypeGuessr
    # Pure orchestrator for DSL type registration.
    # No framework logic, no cache logic — delegates everything to Adapters.
    class DslTypeRegistrar
      def initialize(signature_registry:, code_index:, project_root:, adapters: nil)
        @signature_registry = signature_registry
        @code_index = code_index
        @project_root = project_root
        @adapters = adapters || default_adapters
        @base_registered = false
        @log_callback = nil
      end

      def on_log(&block)
        @log_callback = block
        active_adapters.each { |a| a.on_log(&block) }
      end

      def register_all(runner_client: nil)
        unless @base_registered
          active_adapters.each { |a| a.register_base_methods(signature_registry: @signature_registry) }
          @base_registered = true
        end

        active_adapters.each do |adapter|
          adapter.register_models(
            runner_client: runner_client,
            signature_registry: @signature_registry,
            code_index: @code_index
          )
        end
      end

      def check_and_refresh(runner_client: nil)
        active_adapters.each do |adapter|
          next unless adapter.changed?

          adapter.refresh(
            runner_client: runner_client,
            signature_registry: @signature_registry,
            code_index: @code_index
          )
        end
      end

      private def active_adapters
        @adapters.select(&:applicable?)
      end

      private def default_adapters
        [Dsl::ActiveRecordAdapter.new(project_root: @project_root)]
      end
    end
  end
end
