# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Container mutation methods (Hash#[]=, Array#[]=, Array#<<) for PrismConverter
      class PrismConverter
        # Check if node is a local variable node (for indexed assignment)
        private def local_variable_node?(node)
          node.is_a?(IR::LocalWriteNode) || node.is_a?(IR::LocalReadNode)
        end

        private def extract_literal_type(ir_node)
          case ir_node
          when IR::LiteralNode
            ir_node.type
          else
            Types::Unknown.instance
          end
        end

        private def widen_to_hash_type(original_type, key_arg, value_type)
          # When mixing key types, widen to generic HashType
          new_key_type = infer_key_type(key_arg)

          case original_type
          when Types::HashShape
            # HashShape with symbol keys + non-symbol key -> widen to Hash[Symbol | NewKeyType, ValueUnion]
            original_key_type = Types::ClassInstance.for("Symbol")
            original_value_types = original_type.fields.values.uniq
            all_value_types = (original_value_types + [value_type]).uniq

            combined_key_type = Types::Union.new([original_key_type, new_key_type].uniq)
            combined_value_type = all_value_types.size == 1 ? all_value_types.first : Types::Union.new(all_value_types)

            Types::HashType.new(combined_key_type, combined_value_type)
          when Types::HashType
            # Already a HashType, just union the key and value types
            combined_key_type = union_types(original_type.key_type, new_key_type)
            combined_value_type = union_types(original_type.value_type, value_type)
            Types::HashType.new(combined_key_type, combined_value_type)
          else
            Types::HashType.new(new_key_type, value_type)
          end
        end

        private def union_types(type1, type2)
          return type2 if type1.nil? || type1.is_a?(Types::Unknown)
          return type1 if type2.nil? || type2.is_a?(Types::Unknown)
          return type1 if type1 == type2

          types = []
          types += type1.is_a?(Types::Union) ? type1.types : [type1]
          types += type2.is_a?(Types::Union) ? type2.types : [type2]
          Types::Union.new(types.uniq)
        end

        private def infer_key_type(key_arg)
          case key_arg
          when Prism::SymbolNode
            Types::ClassInstance.for("Symbol")
          when Prism::StringNode
            Types::ClassInstance.for("String")
          when Prism::IntegerNode
            Types::ClassInstance.for("Integer")
          else
            Types::Unknown.instance
          end
        end

        # Check if method is a container mutating method
        private def container_mutating_method?(method, receiver_node)
          return false unless local_variable_node?(receiver_node)

          receiver_type = get_receiver_type(receiver_node)
          return false unless receiver_type

          case method
          when :[]= then hash_like?(receiver_type) || array_like?(receiver_type)
          when :<<  then array_like?(receiver_type)
          else false
          end
        end

        # Get receiver's current type
        private def get_receiver_type(receiver_node)
          return nil unless receiver_node.respond_to?(:write_node)

          write_node = receiver_node.write_node
          return nil unless write_node
          return nil unless write_node.respond_to?(:value)

          value = write_node.value
          return nil unless value.respond_to?(:type)

          value.type
        end

        # Check if type is hash-like
        private def hash_like?(type)
          type.is_a?(Types::HashShape) || type.is_a?(Types::HashType)
        end

        # Check if type is array-like
        private def array_like?(type)
          type.is_a?(Types::ArrayType) || type.is_a?(Types::TupleType)
        end

        # Handle container mutation by creating new LocalWriteNode with merged type
        private def handle_container_mutation(prism_node, receiver_node, args, context)
          merged_type = compute_merged_type(receiver_node, prism_node.name, args, prism_node)
          return receiver_node unless merged_type

          # Block scope + outer variable → widen TupleType to ArrayType
          is_outer_var = context.scope_type == :block && !context.owns_variable?(receiver_node.name)
          merged_type = widen_tuple_to_array(merged_type) if is_outer_var

          # Create new LiteralNode with merged type
          value_node = IR::LiteralNode.new(merged_type, nil, nil, [], receiver_node.loc)

          # Create new LocalWriteNode with merged type
          new_write = IR::LocalWriteNode.new(
            receiver_node.name, value_node, receiver_node.called_methods, convert_loc(prism_node.location)
          )

          # Register for next line references
          context.register_variable(receiver_node.name, new_write)

          # Propagate widened type to parent context (so it's visible after block)
          context.register_variable_in_parent(receiver_node.name, new_write) if is_outer_var

          # Create new LocalReadNode pointing to new write_node
          new_read = IR::LocalReadNode.new(
            receiver_node.name, new_write, receiver_node.called_methods, receiver_node.loc
          )

          # Register the newly created nodes in location_index
          if context.location_index
            context.location_index.add(context.file_path, value_node, context.scope_id)
            context.location_index.add(context.file_path, new_write, context.scope_id)
            context.location_index.add(context.file_path, new_read, context.scope_id)
          end

          new_read
        end

        # Compute merged type for container mutation
        private def compute_merged_type(receiver_node, method, args, prism_node)
          original_type = get_receiver_type(receiver_node)
          return nil unless original_type

          case method
          when :[]=
            if hash_like?(original_type)
              compute_hash_assignment_type(original_type, args, prism_node)
            elsif array_like?(original_type)
              compute_array_assignment_type(original_type, args)
            end
          when :<<
            compute_array_append_type(original_type, args) if array_like?(original_type)
          end
        end

        # Compute Hash type after indexed assignment
        private def compute_hash_assignment_type(original_type, args, prism_node)
          return nil unless args.size == 2

          key_arg = prism_node.arguments.arguments[0]
          value_type = extract_literal_type(args[1])

          case original_type
          when Types::HashShape
            if key_arg.is_a?(Prism::SymbolNode)
              # Symbol key → keep HashShape, add field
              key_name = key_arg.value.to_sym
              Types::HashShape.new(original_type.fields.merge(key_name => value_type))
            else
              # Non-symbol key → widen to HashType
              widen_to_hash_type(original_type, key_arg, value_type)
            end
          when Types::HashType
            # Empty hash (Unknown types) + symbol key → becomes HashShape with one field
            if empty_hash_type?(original_type) && key_arg.is_a?(Prism::SymbolNode)
              key_name = key_arg.value.to_sym
              Types::HashShape.new({ key_name => value_type })
            else
              key_type = infer_key_type(key_arg)
              Types::HashType.new(
                union_types(original_type.key_type, key_type),
                union_types(original_type.value_type, value_type)
              )
            end
          end
        end

        # Check if HashType is empty (has Unknown types)
        private def empty_hash_type?(hash_type)
          (hash_type.key_type.nil? || hash_type.key_type.is_a?(Types::Unknown)) &&
            (hash_type.value_type.nil? || hash_type.value_type.is_a?(Types::Unknown))
        end

        # Compute Array type after indexed assignment
        private def compute_array_assignment_type(original_type, args)
          return nil unless args.size == 2

          value_type = extract_literal_type(args[1])
          case original_type
          when Types::TupleType
            Types::TupleType.new(original_type.element_types + [value_type])
          else
            combined = union_types(original_type.element_type, value_type)
            Types::ArrayType.new(combined)
          end
        end

        # Compute Array type after << operator
        private def compute_array_append_type(original_type, args)
          return nil unless args.size == 1

          value_type = extract_literal_type(args[0])
          case original_type
          when Types::TupleType
            Types::TupleType.new(original_type.element_types + [value_type])
          else
            combined = union_types(original_type.element_type, value_type)
            Types::ArrayType.new(combined)
          end
        end

        # Widen TupleType to ArrayType (for block mutations where position info is meaningless)
        private def widen_tuple_to_array(type)
          return type unless type.is_a?(Types::TupleType)

          unique = type.element_types.uniq
          elem = unique.size == 1 ? unique.first : Types::Union.new(unique)
          Types::ArrayType.new(elem)
        end
      end
    end
  end
end
