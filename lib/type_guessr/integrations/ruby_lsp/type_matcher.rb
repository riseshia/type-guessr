# frozen_string_literal: true

require_relative "../../core/type_matcher"
require_relative "index_adapter"

module TypeGuessr
  module Integrations
    module RubyLsp
      # TypeMatcher finds classes/modules that have all the specified methods
      # This is a compatibility wrapper that delegates to the core implementation
      class TypeMatcher
        def initialize(index)
          adapter = IndexAdapter.new(index)
          @core_matcher = ::TypeGuessr::Core::TypeMatcher.new(adapter)
        end

        # Given a set of method names, find all classes that have ALL those methods
        # @param method_names [Array<String>] the method names to search for
        # @return [Array<String>] class names that have all the specified methods
        def find_matching_types(method_names)
          @core_matcher.find_matching_types(method_names)
        end
      end
    end
  end
end
