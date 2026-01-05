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
        # Callback for resolving duck types to class instances
        # @return [Proc, nil] A proc that takes DuckType and returns resolved type or nil
        attr_accessor :duck_type_resolver

        def initialize(rbs_provider)
          @rbs_provider = rbs_provider
          @cache = {}.compare_by_identity
          @project_methods = {} # { "ClassName" => { "method_name" => DefNode } }
          @duck_type_resolver = nil
        end

        # Register a project method definition for later lookup
        # @param class_name [String] Class name
        # @param method_name [String] Method name
        # @param def_node [IR::DefNode] Method definition node
        def register_method(class_name, method_name, def_node)
          @project_methods[class_name] ||= {}
          @project_methods[class_name][method_name] = def_node
        end

        # Look up a project method definition
        # @param class_name [String] Class name
        # @param method_name [String] Method name
        # @return [IR::DefNode, nil] Method definition node or nil
        def lookup_method(class_name, method_name)
          @project_methods.dig(class_name, method_name)
        end

        # Get all registered class names
        # @return [Array<String>] List of class names (frozen)
        def registered_classes
          @project_methods.keys.freeze
        end

        # Get all methods for a specific class
        # @param class_name [String] Class name
        # @return [Hash<String, IR::DefNode>] Methods hash (frozen)
        def methods_for_class(class_name)
          (@project_methods[class_name] || {}).freeze
        end

        # Search for methods matching a pattern
        # @param pattern [String] Search pattern (partial match on "ClassName#method_name")
        # @return [Array<Array>] Array of [class_name, method_name, def_node]
        def search_methods(pattern)
          results = []
          @project_methods.each do |class_name, methods|
            methods.each do |method_name, def_node|
              full_name = "#{class_name}##{method_name}"
              results << [class_name, method_name, def_node] if full_name.include?(pattern)
            end
          end
          results
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
          when IR::WriteNode
            infer_write(node)
          when IR::ReadNode
            infer_read(node)
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
          when IR::SelfNode
            infer_self(node)
          when IR::ReturnNode
            infer_return(node)
          else
            Result.new(Types::Unknown.instance, "unknown node type", :unknown)
          end
        end

        def infer_literal(node)
          Result.new(node.type, "literal", :literal)
        end

        def infer_write(node)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_read(node)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.write_node

          infer(node.write_node)
        end

        def infer_param(node)
          # Handle special parameter kinds first
          case node.kind
          when :rest
            # Rest parameter (*args) is always Array
            return Result.new(Types::ArrayType.new, "rest parameter", :inference)
          when :keyword_rest
            # Keyword rest parameter (**kwargs) is always Hash
            return Result.new(Types::ClassInstance.new("Hash"), "keyword rest parameter", :inference)
          when :block
            # Block parameter (&block) is always Proc
            return Result.new(Types::ClassInstance.new("Proc"), "block parameter", :inference)
          when :forwarding
            # Forwarding parameter (...) forwards all arguments
            return Result.new(Types::ForwardingArgs.instance, "forwarding parameter", :inference)
          end

          # Try default value for optional parameters
          if node.default_value
            dep_result = infer(node.default_value)
            return Result.new(dep_result.type, "parameter default: #{dep_result.reason}", dep_result.source)
          end

          # Try duck typing based on called methods
          if node.called_methods.any?
            duck_type = Types::DuckType.new(node.called_methods)
            return Result.new(
              duck_type,
              "parameter with duck typing",
              :inference
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
          # Special case: Class method calls (ClassName.method)
          if node.receiver.is_a?(IR::ConstantNode)
            class_name = node.receiver.name

            # ClassName.new returns instance of that class
            if node.method == :new
              return Result.new(
                Types::ClassInstance.new(class_name),
                "#{class_name}.new",
                :inference
              )
            end

            # For other class methods, query RBS singleton type
            arg_types = node.args.map { |arg| infer(arg).type }
            return_type = @rbs_provider.get_class_method_return_type(
              class_name,
              node.method.to_s,
              arg_types
            )

            unless return_type.is_a?(Types::Unknown)
              return Result.new(
                return_type,
                "#{class_name}.#{node.method} (RBS)",
                :rbs
              )
            end
          end

          # Infer receiver type first
          if node.receiver
            receiver_result = infer(node.receiver)
            receiver_type = receiver_result.type

            # Try to resolve DuckType to ClassInstance if possible
            if receiver_type.is_a?(Types::DuckType)
              # First try external resolver (RubyIndexer)
              if @duck_type_resolver
                resolved = @duck_type_resolver.call(receiver_type)
                receiver_type = resolved if resolved && !resolved.is_a?(Types::Unknown)
              end

              # If still DuckType, try project methods
              if receiver_type.is_a?(Types::DuckType)
                resolved = resolve_duck_type_from_project_methods(receiver_type)
                receiver_type = resolved if resolved
              end
            end

            # Query RBS for method return type
            if receiver_type.is_a?(Types::ClassInstance)
              # Infer argument types for overload resolution
              arg_types = node.args.map { |arg| infer(arg).type }
              return_type = @rbs_provider.get_method_return_type_for_args(
                receiver_type.name,
                node.method.to_s,
                arg_types
              )

              # If RBS returns Unknown, try project methods
              if return_type.is_a?(Types::Unknown)
                def_node = lookup_method(receiver_type.name, node.method.to_s)
                if def_node
                  return_result = infer(def_node)
                  return Result.new(
                    return_result.type,
                    "#{receiver_type.name}##{node.method} (project)",
                    :project
                  )
                end
              end

              return Result.new(
                return_type,
                "#{receiver_type.name}##{node.method}",
                :stdlib
              )
            elsif receiver_type.is_a?(Types::ArrayType)
              # Handle Array methods with element type substitution
              elem_type = receiver_type.element_type
              substitutions = { Elem: elem_type }

              # Check for block presence and infer its return type for U substitution
              if node.has_block
                if node.block_body
                  block_result = infer(node.block_body)
                  substitutions[:U] = block_result.type unless block_result.type.is_a?(Types::Unknown)
                else
                  # Empty block returns nil
                  substitutions[:U] = Types::ClassInstance.new("NilClass")
                end
              end

              return_type = @rbs_provider.get_method_return_type_with_substitution(
                "Array",
                node.method.to_s,
                substitutions
              )
              return Result.new(
                return_type,
                "Array[#{elem_type || "untyped"}]##{node.method}",
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
            elsif receiver_type.is_a?(Types::HashType)
              # For Hash, substitute K and V type variables
              block_param_types = @rbs_provider.get_block_param_types_with_substitution(
                "Hash",
                node.call_node.method.to_s,
                key: receiver_type.key_type,
                value: receiver_type.value_type
              )
              if block_param_types.size > node.index
                param_type = block_param_types[node.index]
                return Result.new(
                  param_type,
                  "block param[#{node.index}] from Hash[#{receiver_type.key_type}, #{receiver_type.value_type}]##{node.call_node.method}",
                  :stdlib
                )
              end
            elsif receiver_type.is_a?(Types::HashShape)
              # For HashShape, key type is Symbol and value type is union of all field types
              key_type = Types::ClassInstance.new("Symbol")
              value_types = receiver_type.fields.values.uniq
              value_type = if value_types.size == 1
                             value_types.first
                           else
                             Types::Union.new(value_types)
                           end
              block_param_types = @rbs_provider.get_block_param_types_with_substitution(
                "Hash",
                node.call_node.method.to_s,
                key: key_type,
                value: value_type
              )
              if block_param_types.size > node.index
                param_type = block_param_types[node.index]
                return Result.new(
                  param_type,
                  "block param[#{node.index}] from HashShape##{node.call_node.method}",
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
          # Empty method body returns nil
          unless node.return_node
            return Result.new(
              Types::ClassInstance.new("NilClass"),
              "def #{node.name} returns nil (empty body)",
              :project
            )
          end

          return_result = infer(node.return_node)
          Result.new(
            return_result.type,
            "def #{node.name} returns #{return_result.reason}",
            :project
          )
        end

        def infer_self(node)
          Result.new(
            Types::ClassInstance.new(node.class_name),
            "self in #{node.class_name}",
            :inference
          )
        end

        def infer_return(node)
          if node.value
            value_result = infer(node.value)
            Result.new(value_result.type, "explicit return: #{value_result.reason}", value_result.source)
          else
            Result.new(Types::ClassInstance.new("NilClass"), "explicit return nil", :inference)
          end
        end

        # Resolve DuckType to ClassInstance using registered project methods
        # Returns ClassInstance if exactly one class matches, Union if 2-3 match, nil otherwise
        def resolve_duck_type_from_project_methods(duck_type)
          methods = duck_type.methods.map(&:to_s)
          return nil if methods.empty?

          # Find classes that define all the methods
          matching_classes = @project_methods.keys.select do |class_name|
            class_methods = @project_methods[class_name]&.keys || []
            methods.all? { |m| class_methods.include?(m) }
          end

          case matching_classes.size
          when 0
            nil
          when 1
            Types::ClassInstance.new(matching_classes.first)
          when 2, 3
            types = matching_classes.map { |c| Types::ClassInstance.new(c) }
            Types::Union.new(types)
          end
          # 4+ matches → nil (too ambiguous)
        end
      end
    end
  end
end
