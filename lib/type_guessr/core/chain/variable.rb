# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents a local variable reference
      # Example: user, name, count
      class Variable < Link
        def resolve(context, _receiver_type, is_head)
          return Types::Unknown.instance unless is_head

          # Look up the variable's chain and resolve it recursively
          var_chain = context.lookup_chain(@word)
          return Types::Unknown.instance unless var_chain

          # Create child context with incremented depth
          child_context = context.child
          return Types::Unknown.instance unless child_context

          var_chain.resolve(child_context)
        end
      end

      # Represents an instance variable reference
      # Example: @user, @name, @count
      class InstanceVariable < Link
        def resolve(context, _receiver_type, is_head)
          return Types::Unknown.instance unless is_head

          # Look up the instance variable's chain
          var_chain = context.lookup_chain(@word)
          return Types::Unknown.instance unless var_chain

          # Create child context with incremented depth
          child_context = context.child
          return Types::Unknown.instance unless child_context

          var_chain.resolve(child_context)
        end
      end

      # Represents a class variable reference
      # Example: @@count, @@cache
      class ClassVariable < Link
        def resolve(context, _receiver_type, is_head)
          return Types::Unknown.instance unless is_head

          # Look up the class variable's chain
          var_chain = context.lookup_chain(@word)
          return Types::Unknown.instance unless var_chain

          # Create child context with incremented depth
          child_context = context.child
          return Types::Unknown.instance unless child_context

          var_chain.resolve(child_context)
        end
      end
    end
  end
end
