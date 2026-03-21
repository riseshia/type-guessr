# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Variable read/write and compound assignment methods for PrismConverter
      class PrismConverter
        private def convert_local_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          write_node = IR::LocalWriteNode.new(prism_node.name, value_node, [], convert_loc(prism_node.location))
          context.register_variable(prism_node.name, write_node)
          write_node
        end

        private def convert_local_variable_read(prism_node, context)
          # Look up the most recent assignment
          write_node = context.lookup_variable(prism_node.name)

          IR::LocalReadNode.new(
            prism_node.name,
            write_node,
            # Share called_methods array for method-based inference
            # nil case: rescue binding (=> e), pattern matching binding, etc. (not yet implemented)
            write_node&.called_methods || [],
            convert_loc(prism_node.location)
          )
        end

        private def convert_instance_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)
          class_name = context.current_class_name

          write_node = IR::InstanceVariableWriteNode.new(
            prism_node.name,
            class_name,
            value_node,
            # Share called_methods with value node for type propagation
            # nil case: value is an unhandled node type (convert() returns nil)
            value_node&.called_methods || [],
            convert_loc(prism_node.location)
          )
          # Register at class level so it's visible across methods
          context.register_instance_variable(prism_node.name, write_node)
          write_node
        end

        private def convert_instance_variable_read(prism_node, context)
          # Look up from class level first
          write_node = context.lookup_instance_variable(prism_node.name)

          IR::InstanceVariableReadNode.new(
            prism_node.name,
            context.current_class_name,
            write_node,
            # Share called_methods array for method-based inference
            # nil case: instance variable read before any assignment in current file
            write_node&.called_methods || [],
            convert_loc(prism_node.location)
          )
        end

        private def convert_class_variable_write(prism_node, context)
          value_node = convert(prism_node.value, context)

          write_node = IR::ClassVariableWriteNode.new(
            prism_node.name,
            context.current_class_name,
            value_node,
            # Share called_methods with value node for type propagation
            # nil case: value is an unhandled node type (e.g., LambdaNode)
            value_node&.called_methods || [],
            convert_loc(prism_node.location)
          )
          context.register_variable(prism_node.name, write_node)
          write_node
        end

        private def convert_class_variable_read(prism_node, context)
          write_node = context.lookup_variable(prism_node.name)

          IR::ClassVariableReadNode.new(
            prism_node.name,
            context.current_class_name,
            write_node,
            # Share called_methods array for method-based inference
            # nil case: class variable read before any assignment in current file
            write_node&.called_methods || [],
            convert_loc(prism_node.location)
          )
        end

        # Compound assignment: x ||= value
        # Result type is union of original and new value type
        private def convert_local_variable_or_write(prism_node, context)
          convert_or_write(prism_node, context, :local)
        end

        # Compound assignment: x &&= value
        # Result type is union of original and new value type
        private def convert_local_variable_and_write(prism_node, context)
          convert_and_write(prism_node, context, :local)
        end

        # Compound assignment: x += value, x -= value, etc.
        # Result type depends on the operator method return type
        private def convert_local_variable_operator_write(prism_node, context)
          convert_operator_write(prism_node, context, :local)
        end

        private def convert_instance_variable_or_write(prism_node, context)
          convert_or_write(prism_node, context, :instance)
        end

        private def convert_instance_variable_and_write(prism_node, context)
          convert_and_write(prism_node, context, :instance)
        end

        private def convert_instance_variable_operator_write(prism_node, context)
          convert_operator_write(prism_node, context, :instance)
        end

        # Generic ||= handler
        # x ||= value means: if x is nil/false, x = value, else keep x
        # Uses OrNode to apply truthiness filtering (removes nil/false from LHS)
        private def convert_or_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          or_node = if original_node
                      IR::OrNode.new(
                        original_node,
                        value_node,
                        [],
                        convert_loc(prism_node.location)
                      )
                    else
                      value_node
                    end

          write_node = create_write_node(prism_node.name, kind, or_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Generic &&= handler
        # x &&= value means: if x is truthy, x = value, else keep x
        # Type is union of original type and value type
        private def convert_and_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          # Create merge node for union type (original | value)
          branches = []
          branches << original_node if original_node
          branches << value_node

          merge_node = if branches.size == 1
                         branches.first
                       else
                         IR::MergeNode.new(
                           branches,
                           [],
                           convert_loc(prism_node.location)
                         )
                       end

          write_node = create_write_node(prism_node.name, kind, merge_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Generic operator write handler (+=, -=, *=, etc.)
        # x += value is equivalent to x = x.+(value)
        # Type is the return type of the operator method
        private def convert_operator_write(prism_node, context, kind)
          original_node = lookup_by_kind(prism_node.name, kind, context)
          value_node = convert(prism_node.value, context)

          # Create a call node representing x.operator(value)
          call_node = IR::CallNode.new(
            prism_node.binary_operator, original_node, [value_node], [], nil, false, [], convert_loc(prism_node.location)
          )

          # Create write node with call result as value
          write_node = create_write_node(prism_node.name, kind, call_node, context, prism_node.location)
          register_by_kind(prism_node.name, write_node, kind, context)
          write_node
        end

        # Helper to create the appropriate write node type based on kind
        private def create_write_node(name, kind, value, context, location)
          loc = convert_loc(location)
          case kind
          when :local
            IR::LocalWriteNode.new(name, value, [], loc)
          when :instance
            IR::InstanceVariableWriteNode.new(name, context.current_class_name, value, [], loc)
          when :class
            IR::ClassVariableWriteNode.new(name, context.current_class_name, value, [], loc)
          end
        end

        # Helper to lookup variable by kind
        private def lookup_by_kind(name, kind, context)
          case kind
          when :instance
            context.lookup_instance_variable(name)
          else
            context.lookup_variable(name)
          end
        end

        # Helper to register variable by kind
        private def register_by_kind(name, node, kind, context)
          case kind
          when :instance
            context.register_instance_variable(name, node)
          else
            context.register_variable(name, node)
          end
        end
      end
    end
  end
end
