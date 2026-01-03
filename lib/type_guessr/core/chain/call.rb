# frozen_string_literal: true

require_relative "link"

module TypeGuessr
  module Core
    class Chain
      # Represents a method call
      # Examples: .find(1), .upcase, .each { }
      class Call < Link
        attr_reader :arguments, :has_block

        def initialize(word, arguments: [], has_block: false)
          super(word)
          @arguments = arguments.freeze # Array of Chain for arguments
          @has_block = has_block
        end

        def resolve(context, receiver_type, is_head)
          # If head and no receiver, this is a local method call (not supported yet)
          return Types::Unknown.instance if is_head && receiver_type.nil?

          # Receiver must be known
          return Types::Unknown.instance unless receiver_type
          return Types::Unknown.instance if receiver_type == Types::Unknown.instance

          class_name = extract_class_name(receiver_type)
          return Types::Unknown.instance unless class_name

          # 1. Try RBS first
          rbs_type = context.get_method_return_type(class_name, @word)
          return rbs_type if rbs_type != Types::Unknown.instance

          # 2. Try user-defined methods via UserMethodReturnResolver (file-based)
          user_type = context.get_user_method_return_type(class_name, @word)
          return user_type if user_type != Types::Unknown.instance

          # 3. Try ChainIndex (AST-based method return chains)
          return_chains = context.get_method_return_chains(class_name, @word)
          if return_chains.any?
            types = return_chains.map { |chain| chain.resolve(context) }
            types = types.reject { |t| t == Types::Unknown.instance }.uniq

            return case types.size
                   when 0 then Types::Unknown.instance
                   when 1 then types.first
                   else Types::Union.new(types)
                   end
          end

          # 4. Return Unknown if nothing works
          Types::Unknown.instance
        end

        def ==(other)
          super && @arguments == other.arguments && @has_block == other.has_block
        end

        def hash
          [self.class, @word, @arguments, @has_block].hash
        end

        private

        # Extract class name from a Types object
        def extract_class_name(type)
          case type
          when Types::ClassInstance then type.name
          when Types::ArrayType then "Array"
          when Types::HashShape then "Hash"
          end
        end
      end
    end
  end
end
