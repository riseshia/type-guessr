# frozen_string_literal: true

require "ruby_lsp/type_inferrer"

module TypeGuessr
  module Core
    # Custom TypeInferrer that inherits from ruby-lsp's TypeInferrer.
    # This allows TypeGuessr to hook into ruby-lsp's type inference system
    # for enhanced heuristic type guessing while reusing Type and GuessedType classes.
    class TypeInferrer < ::RubyLsp::TypeInferrer
      # Infers the type of a node based on its context.
      # Override this method to add heuristic type inference.
      #
      # @param node_context [RubyLsp::NodeContext] The context of the node
      # @return [Type, GuessedType, nil] The inferred type or nil if unknown
      # rubocop:disable Lint/UselessMethodDefinition
      def infer_receiver_type(node_context)
        super
      end
      # rubocop:enable Lint/UselessMethodDefinition
    end
  end
end
