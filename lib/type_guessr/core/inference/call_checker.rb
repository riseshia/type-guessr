# frozen_string_literal: true

require_relative "../types"

module TypeGuessr
  module Core
    module Inference
      # Asks the code index whether an inferred type can answer the methods
      # called on it. Duck typing already guarantees this by construction for
      # receivers it resolves; this closes the gap for receivers whose type came
      # from elsewhere (literals, `.new`, RBS return types) and for arity, which
      # candidate lookup does not check.
      #
      # Only an index that can answer existence takes part — the static
      # RubyIndexer-backed adapter has no `method_defined?`, so it never judges.
      class CallChecker
        # @param code_index [#method_defined?, #constant_kind, nil]
        def initialize(code_index)
          @code_index = code_index
        end

        def active?
          @code_index.respond_to?(:method_defined?)
        end

        # Calls the type cannot answer.
        # @param type [Types::Type]
        # @param called_methods [Array<IR::CalledMethod>]
        # @return [Array<Array(IR::CalledMethod, Symbol)>] [call, :missing | :arity]
        def missing_methods(type, called_methods)
          return [] unless active?
          # A bare `nil` type comes from `x = nil` before a loop fills x in;
          # flow-insensitive analysis attaches the later calls to that write, so
          # it says nothing about the real receiver.
          return [] if nil_type?(type)

          receivers = expand_receivers(type)
          return [] if receivers.nil? || receivers.empty?

          seen = {}
          called_methods.filter_map do |cm|
            signature = call_signature(cm)
            next if seen[signature]

            seen[signature] = true

            answers = receivers.map { |class_name, singleton| receiver_answer(class_name, singleton, signature) }
            # nil = class unknown to the index, true = callable: not evidence of absence.
            next if answers.any? { |a| a.nil? || a == true }

            [cm, answers.all? { |a| a == "arity" } ? :arity : :missing]
          end
        end

        # Human-readable verdict. Absent methods and arity mismatches read differently.
        # @param type [Types::Type]
        # @param missing [Array<Array(IR::CalledMethod, Symbol)>] from #missing_methods
        # @return [String]
        def reason(type, missing)
          absent = missing.filter_map { |cm, cause| cm.name.to_s if cause == :missing }.uniq
          parts = []
          parts << "#{type} does not define #{absent.join(", ")}" if absent.any?
          missing.each do |cm, cause|
            parts << "#{type}##{cm.name} does not accept #{describe_call_args(cm)}" if cause == :arity
          end
          parts.join("; ")
        end

        # True when the type is exactly `nil` — a NilClass member inside a Union
        # still answers normally.
        private def nil_type?(type)
          type.is_a?(Types::ClassInstance) && type.name == "NilClass"
        end

        # Flatten a type into the receivers a call would dispatch on.
        # @return [Array<Array(String, Boolean)>, nil] [class_name, singleton] pairs,
        #   or nil if any part of the type has no class to check against
        private def expand_receivers(type)
          case type
          when Types::Union
            type.types.each_with_object([]) do |member, acc|
              sub = expand_receivers(member)
              return nil unless sub

              acc.concat(sub)
            end
          when Types::SingletonType
            [[type.name, true]]
          else
            class_name = type.rbs_class_name
            class_name ? [[class_name, false]] : nil
          end
        end

        # @return [Array(String, Integer?, Array<String>)] name, positional count, keywords
        private def call_signature(called_method)
          [called_method.name.to_s, called_method.positional_count, (called_method.keywords || []).map(&:to_s)]
        end

        private def receiver_answer(class_name, singleton, signature)
          # A value cannot be an instance of a module, so an instance-level module
          # receiver means the inferred type is wrong — answer "unknown".
          # `MyModule.helper` is a real call, so singleton receivers stay checkable.
          return nil if !singleton && @code_index.constant_kind(class_name) == :module

          method_name, positional_count, keywords = signature
          @code_index.method_defined?(class_name, method_name, singleton: singleton,
                                                               positional_count: positional_count, keywords: keywords)
        end

        private def describe_call_args(called_method)
          parts = []
          count = called_method.positional_count
          parts << "#{count} positional argument#{"s" unless count == 1}" if count
          keywords = called_method.keywords || []
          parts << "keyword#{"s" if keywords.size > 1} #{keywords.map { |k| "#{k}:" }.join(", ")}" if keywords.any?
          parts.empty? ? "these arguments" : parts.join(" + ")
        end
      end
    end
  end
end
