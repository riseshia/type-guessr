# frozen_string_literal: true

require_relative "../ir/nodes"
require_relative "../types"
require_relative "result"

module TypeGuessr
  module Core
    module Inference
      # Resolves types by traversing the IR dependency graph
      # Each node points to nodes it depends on (reverse dependency graph)
      class Resolver
        def initialize(rbs_provider)
          @rbs_provider = rbs_provider
          @cache = {}.compare_by_identity
        end

        # Infer the type of an IR node
        # @param node [IR::Node] IR node to infer type for
        # @return [Result] Inference result with type and reason
        def infer(node)
          return Result.new(Types::Unknown.instance, "no node", :unknown) unless node

          # Use cache to avoid redundant inference
          cached = @cache[node]
          return cached if cached

          result = infer_node(node)
          @cache[node] = result
          result
        end

        # Clear the inference cache
        def clear_cache
          @cache.clear
        end

        private

        def infer_node(node)
          case node
          when IR::LiteralNode
            infer_literal(node)
          when IR::VariableNode
            infer_variable(node)
          when IR::ParamNode
            infer_param(node)
          when IR::ConstantNode
            infer_constant(node)
          when IR::CallNode
            infer_call(node)
          when IR::BlockParamSlot
            infer_block_param_slot(node)
          when IR::MergeNode
            infer_merge(node)
          when IR::DefNode
            infer_def(node)
          else
            Result.new(Types::Unknown.instance, "unknown node type", :unknown)
          end
        end

        def infer_literal(node)
          Result.new(node.type, "literal", :literal)
        end

        def infer_variable(node)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.dependency

          dep_result = infer(node.dependency)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_param(node)
          # Try default value first
          if node.default_value
            dep_result = infer(node.default_value)
            return Result.new(dep_result.type, "parameter default: #{dep_result.reason}", dep_result.source)
          end

          # Try duck typing based on called methods
          if node.called_methods.any?
            # For now, return Unknown with methods info
            # In full implementation, this would query an index for matching types
            methods_str = node.called_methods.join(", ")
            return Result.new(
              Types::Unknown.instance,
              "parameter with methods: #{methods_str}",
              :unknown
            )
          end

          Result.new(Types::Unknown.instance, "parameter without type info", :unknown)
        end

        def infer_constant(node)
          return Result.new(Types::Unknown.instance, "undefined constant", :unknown) unless node.dependency

          dep_result = infer(node.dependency)
          Result.new(dep_result.type, "constant #{node.name}: #{dep_result.reason}", dep_result.source)
        end

        def infer_call(node)
          # Infer receiver type first
          if node.receiver
            receiver_result = infer(node.receiver)
            receiver_type = receiver_result.type

            # Query RBS for method return type
            if receiver_type.is_a?(Types::ClassInstance)
              return_type = @rbs_provider.get_method_return_type(receiver_type.name, node.method.to_s)
              return Result.new(
                return_type,
                "#{receiver_type.name}##{node.method}",
                :stdlib
              )
            elsif receiver_type.is_a?(Types::ArrayType) && receiver_type.element_type.is_a?(Types::ClassInstance)
              # Handle Array methods with element type substitution
              elem_type = receiver_type.element_type
              substitutions = { Elem: elem_type }
              return_type = @rbs_provider.get_method_return_type_with_substitution(
                "Array",
                node.method.to_s,
                substitutions
              )
              return Result.new(
                return_type,
                "Array[#{elem_type}]##{node.method}",
                :stdlib
              )
            end
          end

          # Method call without receiver or unknown receiver type
          Result.new(Types::Unknown.instance, "call #{node.method} on unknown receiver", :unknown)
        end

        def infer_block_param_slot(node)
          # Get the type of the call node
          infer(node.call_node)

          # Try to get block parameter types from RBS
          if node.call_node.receiver
            receiver_result = infer(node.call_node.receiver)
            receiver_type = receiver_result.type

            if receiver_type.is_a?(Types::ArrayType) && receiver_type.element_type
              # For Array, block parameter is the element type
              elem_type = receiver_type.element_type
              if node.index.zero?
                return Result.new(
                  elem_type,
                  "block param from Array[#{elem_type}]##{node.call_node.method}",
                  :stdlib
                )
              end
            elsif receiver_type.is_a?(Types::ClassInstance)
              # Query RBS for block parameter types
              block_param_types = @rbs_provider.get_block_param_types(
                receiver_type.name,
                node.call_node.method.to_s
              )
              if block_param_types.size > node.index
                param_type = block_param_types[node.index]
                return Result.new(
                  param_type,
                  "block param[#{node.index}] from #{receiver_type.name}##{node.call_node.method}",
                  :stdlib
                )
              end
            end
          end

          Result.new(Types::Unknown.instance, "block param without type info", :unknown)
        end

        def infer_merge(node)
          # Infer types from all branches and create union
          branch_results = node.branches.map { |branch| infer(branch) }
          branch_types = branch_results.map(&:type)

          union_type = if branch_types.size == 1
                         branch_types.first
                       else
                         Types::Union.new(branch_types)
                       end

          reasons = branch_results.map(&:reason).uniq.join(" | ")
          Result.new(union_type, "branch merge: #{reasons}", :unknown)
        end

        def infer_def(node)
          # Infer return type from the return node
          return Result.new(Types::Unknown.instance, "method without body", :unknown) unless node.return_node

          return_result = infer(node.return_node)
          Result.new(
            return_result.type,
            "def #{node.name} returns #{return_result.reason}",
            :project
          )
        end
      end
    end
  end
end
