# frozen_string_literal: true

module TypeGuessr
  module Core
    module Converter
      # Method call, block, and call-related helper methods for PrismConverter
      class PrismConverter
        private def convert_call(prism_node, context)
          # Convert receiver - if nil and inside a class, create implicit SelfNode
          receiver_node = if prism_node.receiver
                            convert(prism_node.receiver, context)
                          elsif context.current_class_name
                            IR::SelfNode.new(
                              context.current_class_name,
                              context.in_singleton_method,
                              [],
                              convert_loc(prism_node.location)
                            )
                          end

          args = prism_node.arguments&.arguments&.map { |arg| convert(arg, context) } || []

          has_block = !prism_node.block.nil?

          # Track method call on receiver for method-based type inference
          if variable_node?(receiver_node) && receiver_node.called_methods.none? { |cm| cm.name == prism_node.name }
            receiver_node.called_methods << build_called_method(prism_node)
          end

          # Handle container mutating methods (Hash#[]=, Array#[]=, Array#<<)
          receiver_node = handle_container_mutation(prism_node, receiver_node, args, context) if container_mutating_method?(prism_node.name, receiver_node)

          # Use message_loc for method name position to match hover lookup
          call_loc = convert_loc(prism_node.message_loc || prism_node.location)
          call_node = IR::CallNode.new(
            prism_node.name, receiver_node, args, [], nil, has_block, [], call_loc
          )

          # Handle block if present (but not block arguments like &block)
          if prism_node.block.is_a?(Prism::BlockNode)
            block_body = convert_block(prism_node.block, call_node, context)
            # Update block_body and has_block on mutable Struct
            call_node.block_body = block_body
            call_node.has_block = true
          end

          call_node
        end

        # Check if node is any variable node (for method call tracking)
        private def variable_node?(node)
          node.is_a?(IR::LocalWriteNode) ||
            node.is_a?(IR::LocalReadNode) ||
            node.is_a?(IR::InstanceVariableWriteNode) ||
            node.is_a?(IR::InstanceVariableReadNode) ||
            node.is_a?(IR::ClassVariableWriteNode) ||
            node.is_a?(IR::ClassVariableReadNode) ||
            node.is_a?(IR::ParamNode) ||
            node.is_a?(IR::BlockParamSlot)
        end

        # Build CalledMethod with signature information from Prism CallNode
        private def build_called_method(prism_node)
          positional_count, has_splat, keywords = extract_call_signature(prism_node)

          IR::CalledMethod.new(
            name: prism_node.name,
            positional_count: has_splat ? nil : positional_count,
            keywords: keywords
          )
        end

        # Extract positional count, splat presence, and keywords from call arguments
        # @return [Array(Integer, Boolean, Array<Symbol>)] [positional_count, has_splat, keywords]
        private def extract_call_signature(prism_node)
          arguments = prism_node.arguments&.arguments || []
          positional_count = 0
          has_splat = false
          keywords = []

          arguments.each do |arg|
            case arg
            when Prism::SplatNode
              has_splat = true
            when Prism::KeywordHashNode
              extract_keywords_from_hash(arg, keywords)
            else
              positional_count += 1
            end
          end

          [positional_count, has_splat, keywords]
        end

        # Extract keyword argument names from KeywordHashNode
        private def extract_keywords_from_hash(hash_node, keywords)
          hash_node.elements.each do |element|
            next unless element.is_a?(Prism::AssocNode)

            key = element.key
            keywords << key.value.to_sym if key.is_a?(Prism::SymbolNode)
          end
        end

        # Extract IR param nodes from a Prism parameter node
        # Handles destructuring (MultiTargetNode) by flattening nested params
        private def extract_param_nodes(param, kind, context, default_value: nil)
          case param
          when Prism::MultiTargetNode
            # Destructuring parameter like (a, b) - extract all nested params
            param.lefts.flat_map { |p| extract_param_nodes(p, kind, context) } +
              param.rights.flat_map { |p| extract_param_nodes(p, kind, context) }
          when Prism::RequiredParameterNode, Prism::OptionalParameterNode
            param_node = IR::ParamNode.new(param.name, kind, default_value, [], convert_loc(param.location))
            context.register_variable(param.name, param_node)
            [param_node]
          else
            []
          end
        end

        private def convert_block(block_node, call_node, context)
          # Create block parameter slots and register them in context
          block_context = context.fork(:block)

          if block_node.parameters.is_a?(Prism::BlockParametersNode)
            parameters_node = block_node.parameters.parameters
            if parameters_node
              # Collect all parameters in order
              params = []
              params.concat(parameters_node.requireds) if parameters_node.requireds
              params.concat(parameters_node.optionals) if parameters_node.optionals

              params.each_with_index do |param, index|
                param_name, param_loc = case param
                                        when Prism::RequiredParameterNode
                                          [param.name, param.location]
                                        when Prism::OptionalParameterNode
                                          [param.name, param.location]
                                        when Prism::MultiTargetNode
                                          # Destructuring parameters like |a, (b, c)|
                                          # For now, skip complex cases
                                          next
                                        else
                                          next
                                        end

                slot = IR::BlockParamSlot.new(index, call_node, [], convert_loc(param_loc))
                call_node.block_params << slot
                block_context.register_variable(param_name, slot)
              end
            end
          end

          # Convert block body and return it for block return type inference
          block_node.body ? convert(block_node.body, block_context) : nil
        end
      end
    end
  end
end
