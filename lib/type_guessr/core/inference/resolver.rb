# frozen_string_literal: true

require_relative "../ir/nodes"
require_relative "../types"
require_relative "../type_simplifier"
require_relative "../registry/method_registry"
require_relative "../registry/variable_registry"
require_relative "result"

module TypeGuessr
  module Core
    module Inference
      # Resolves types by traversing the IR dependency graph
      # Each node points to nodes it depends on (reverse dependency graph)
      class Resolver
        # Callback for resolving method lists to class instances
        # @return [Proc, nil] A proc that takes Array<Symbol> and returns resolved type or nil
        attr_accessor :method_list_resolver

        # Callback for getting class ancestors
        # @return [Proc, nil] A proc that takes class_name and returns array of ancestor names
        attr_accessor :ancestry_provider

        # Callback for checking if a constant is a class or module
        # @return [Proc, nil] A proc that takes constant_name and returns :class, :module, or nil
        attr_accessor :constant_kind_provider

        # Callback for looking up class methods via RubyIndexer
        # @return [Proc, nil] A proc that takes (class_name, method_name) and returns owner_name or nil
        attr_accessor :class_method_lookup_provider

        # Type simplifier for normalizing union types
        # @return [TypeSimplifier, nil]
        attr_accessor :type_simplifier

        # Method registry for storing and looking up project method definitions
        # @return [Registry::MethodRegistry]
        attr_reader :method_registry

        # Variable registry for storing and looking up instance/class variables
        # @return [Registry::VariableRegistry]
        attr_reader :variable_registry

        # @param signature_provider [SignatureProvider] Provider for RBS method signatures
        # @param method_registry [Registry::MethodRegistry, nil] Registry for project methods
        # @param variable_registry [Registry::VariableRegistry, nil] Registry for variables
        def initialize(signature_provider, method_registry: nil, variable_registry: nil)
          @signature_provider = signature_provider
          @method_registry = method_registry || Registry::MethodRegistry.new
          @variable_registry = variable_registry || Registry::VariableRegistry.new
          @cache = {}.compare_by_identity
          @method_list_resolver = nil
          @ancestry_provider = nil
          @constant_kind_provider = nil
          @class_method_lookup_provider = nil
          @type_simplifier = nil
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

          # Apply type simplification if available
          result = simplify_result(result) if @type_simplifier

          @cache[node] = result
          result
        end

        # Clear the inference cache
        def clear_cache
          @cache.clear
        end

        # Convert a list of matching class names to a type
        # @param classes [Array<String>] List of class names
        # @return [Type, nil] ClassInstance (1 match), Union (2-3 matches), or nil
        def classes_to_type(classes)
          case classes.size
          when 0
            nil
          when 1
            Types::ClassInstance.new(classes.first)
          when 2, 3
            types = classes.map { |c| Types::ClassInstance.new(c) }
            Types::Union.new(types)
          end
          # 4+ matches → nil (too ambiguous)
        end

        private

        def infer_node(node)
          case node
          when IR::LiteralNode
            infer_literal(node)
          when IR::LocalWriteNode
            infer_local_write(node)
          when IR::LocalReadNode
            infer_local_read(node)
          when IR::InstanceVariableWriteNode
            infer_instance_variable_write(node)
          when IR::InstanceVariableReadNode
            infer_instance_variable_read(node)
          when IR::ClassVariableWriteNode
            infer_class_variable_write(node)
          when IR::ClassVariableReadNode
            infer_class_variable_read(node)
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

        def infer_local_write(node)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_local_read(node)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.write_node

          write_result = infer(node.write_node)

          # If type is Unknown (or Union of only Unknown), try to resolve from called_methods
          type_is_unknown = write_result.type.is_a?(Types::Unknown) ||
                            (write_result.type.is_a?(Types::Union) &&
                             write_result.type.types.all? { |t| t.is_a?(Types::Unknown) })

          if type_is_unknown && node.called_methods.any?
            resolved_type = resolve_called_methods(node.called_methods)
            if resolved_type
              return Result.new(
                resolved_type,
                "variable inferred from #{node.called_methods.join(", ")}",
                :inference
              )
            end
          end

          write_result
        end

        def infer_instance_variable_write(node)
          return Result.new(Types::Unknown.instance, "unassigned instance variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_instance_variable_read(node)
          write_node = node.write_node

          # Deferred lookup: if write_node is nil at conversion time, try registry
          write_node = @variable_registry.lookup_instance_variable(node.class_name, node.name) if write_node.nil? && node.class_name

          return Result.new(Types::Unknown.instance, "unassigned instance variable", :unknown) unless write_node

          infer(write_node)
        end

        def infer_class_variable_write(node)
          return Result.new(Types::Unknown.instance, "unassigned class variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_class_variable_read(node)
          write_node = node.write_node

          # Deferred lookup: if write_node is nil at conversion time, try registry
          write_node = @variable_registry.lookup_class_variable(node.class_name, node.name) if write_node.nil? && node.class_name

          return Result.new(Types::Unknown.instance, "unassigned class variable", :unknown) unless write_node

          infer(write_node)
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

          # Try to resolve type from called methods
          if node.called_methods.any?
            resolved_type = resolve_called_methods(node.called_methods)
            if resolved_type
              return Result.new(
                resolved_type,
                "parameter inferred from #{node.called_methods.join(", ")}",
                :project
              )
            end

            return Result.new(
              Types::Unknown.instance,
              "parameter with unresolved methods: #{node.called_methods.join(", ")}",
              :unknown
            )
          end

          Result.new(Types::Unknown.instance, "parameter without type info", :unknown)
        end

        def infer_constant(node)
          # If there's a dependency (e.g., constant write), infer from it
          if node.dependency
            dep_result = infer(node.dependency)
            return Result.new(dep_result.type, "constant #{node.name}: #{dep_result.reason}", dep_result.source)
          end

          # Check if constant is a class or module using RubyIndexer
          if @constant_kind_provider
            kind = @constant_kind_provider.call(node.name)
            if %i[class module].include?(kind)
              return Result.new(
                Types::SingletonType.new(node.name),
                "class constant #{node.name}",
                :inference
              )
            end
          end

          Result.new(Types::Unknown.instance, "undefined constant", :unknown)
        end

        def infer_call(node)
          # Special case: Class method calls (ClassName.method)
          if node.receiver.is_a?(IR::ConstantNode)
            # Resolve constant first (handles aliases like RecipeAlias = Recipe)
            receiver_result = infer(node.receiver)
            class_name = case receiver_result.type
                         when Types::SingletonType then receiver_result.type.name
                         else node.receiver.name
                         end

            result = infer_class_method_call(class_name, node)
            return result if result
          end

          # Infer receiver type first
          if node.receiver
            receiver_result = infer(node.receiver)
            receiver_type = receiver_result.type

            # Query for method return type: project first, then RBS
            case receiver_type
            when Types::SingletonType
              result = infer_class_method_call(receiver_type.name, node)
              return result if result
            when Types::ClassInstance
              # 1. Try project methods first
              def_node = @method_registry.lookup(receiver_type.name, node.method.to_s)
              if def_node
                return_result = infer(def_node)
                return Result.new(
                  return_result.type,
                  "#{receiver_type.name}##{node.method} (project)",
                  :project
                )
              end

              # 2. Fall back to RBS signature provider
              arg_types = node.args.map { |arg| infer(arg).type }
              return_type = @signature_provider.get_method_return_type(
                receiver_type.name,
                node.method.to_s,
                arg_types
              )

              # Fall back to Object if class-specific lookup returns Unknown
              if return_type.is_a?(Types::Unknown) && receiver_type.name != "Object"
                return_type = @signature_provider.get_method_return_type(
                  "Object",
                  node.method.to_s,
                  arg_types
                )
              end

              # Substitute self with receiver type
              return_type = return_type.substitute({ self: receiver_type })

              return Result.new(
                return_type,
                "#{receiver_type.name}##{node.method}",
                :stdlib
              )
            when Types::ArrayType
              # Handle Array methods with element type substitution
              substitutions = build_substitutions(receiver_type)

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

              # Get raw return type, then substitute type variables
              raw_return_type = @signature_provider.get_method_return_type("Array", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "Array[#{receiver_type.element_type || "untyped"}]##{node.method}",
                :stdlib
              )
            when Types::HashShape
              # Handle HashShape field access with [] method
              if node.method == :[] && node.args.size == 1
                key_result = infer_hash_shape_access(receiver_type, node.args.first)
                return key_result if key_result
              end

              # Fall back to Hash RBS for other methods
              substitutions = build_substitutions(receiver_type)
              raw_return_type = @signature_provider.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "HashShape##{node.method}",
                :stdlib
              )
            when Types::HashType
              # Handle generic HashType
              substitutions = build_substitutions(receiver_type)
              raw_return_type = @signature_provider.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "Hash[#{receiver_type.key_type}, #{receiver_type.value_type}]##{node.method}",
                :stdlib
              )
            end

            # Try to infer Unknown receiver type from method uniqueness
            # Also handle Union types that are effectively Unknown (only contain Unknown)
            receiver_is_unknown = receiver_type.is_a?(Types::Unknown) ||
                                  (receiver_type.is_a?(Types::Union) &&
                                   receiver_type.types.all? { |t| t.is_a?(Types::Unknown) })
            if receiver_is_unknown
              inferred_receiver = resolve_called_methods([node.method])
              if inferred_receiver.is_a?(Types::ClassInstance)
                # Try project methods with inferred receiver type
                def_node = @method_registry.lookup(inferred_receiver.name, node.method.to_s)
                if def_node
                  return_result = infer(def_node)
                  return Result.new(
                    return_result.type,
                    "#{inferred_receiver.name}##{node.method} (inferred receiver)",
                    :project
                  )
                end

                # Fall back to RBS
                arg_types = node.args.map { |arg| infer(arg).type }
                return_type = @signature_provider.get_method_return_type(
                  inferred_receiver.name,
                  node.method.to_s,
                  arg_types
                )
                return Result.new(
                  return_type,
                  "#{inferred_receiver.name}##{node.method} (inferred receiver)",
                  :stdlib
                )
              end
            end
          end

          # Method call without receiver or unknown receiver type
          # First, try to lookup top-level method
          def_node = @method_registry.lookup("", node.method.to_s)
          if def_node
            return_type = infer(def_node.return_node)
            return Result.new(return_type.type, "top-level method #{node.method}", :project)
          end

          # Fallback to Object to query RBS for common methods (==, to_s, etc.)
          arg_types = node.args.map { |arg| infer(arg).type }
          return_type = @signature_provider.get_method_return_type("Object", node.method.to_s, arg_types)
          # Substitute self with receiver type if available (e.g., Object#dup returns self)
          return_type = return_type.substitute({ self: receiver_type }) if receiver_type
          return Result.new(return_type, "Object##{node.method}", :stdlib) unless return_type.is_a?(Types::Unknown)

          Result.new(Types::Unknown.instance, "call #{node.method} on unknown receiver", :unknown)
        end

        def infer_block_param_slot(node)
          return Result.new(Types::Unknown.instance, "block param without type info", :unknown) unless node.call_node.receiver

          receiver_type = infer(node.call_node.receiver).type
          class_name = receiver_type.rbs_class_name
          return Result.new(Types::Unknown.instance, "block param without type info", :unknown) unless class_name

          # Get block parameter types (returns internal types with TypeVariables)
          raw_block_param_types = @signature_provider.get_block_param_types(class_name, node.call_node.method.to_s)

          # Fall back to Object if class-specific lookup returns empty
          if raw_block_param_types.empty? && class_name != "Object"
            raw_block_param_types = @signature_provider.get_block_param_types("Object", node.call_node.method.to_s)
          end

          return Result.new(Types::Unknown.instance, "block param without type info", :unknown) unless raw_block_param_types.size > node.index

          # Type#substitute applies type variable and self substitutions
          raw_type = raw_block_param_types[node.index]
          resolved_type = raw_type.substitute(build_substitutions(receiver_type))

          Result.new(resolved_type, "block param from #{class_name}##{node.call_node.method}", :stdlib)
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
          # initialize always returns self (the class instance)
          if node.name == :initialize && node.class_name
            return Result.new(
              Types::SelfType.instance,
              "def #{node.name} returns self",
              :project
            )
          end

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
          type = if node.singleton
                   Types::SingletonType.new(node.class_name)
                 else
                   Types::ClassInstance.new(node.class_name)
                 end
          Result.new(type, "self in #{node.class_name}", :inference)
        end

        def infer_return(node)
          if node.value
            value_result = infer(node.value)
            Result.new(value_result.type, "explicit return: #{value_result.reason}", value_result.source)
          else
            Result.new(Types::ClassInstance.new("NilClass"), "explicit return nil", :inference)
          end
        end

        # Infer class method call (ClassName.method or self.method in singleton context)
        # @param class_name [String] The class name
        # @param node [IR::CallNode] The call node
        # @return [Result, nil] The result if resolved, nil otherwise
        def infer_class_method_call(class_name, node)
          # ClassName.new returns instance of that class
          if node.method == :new
            return Result.new(
              Types::ClassInstance.new(class_name),
              "#{class_name}.new",
              :inference
            )
          end

          # Try project class methods first (includes extended module methods)
          if @class_method_lookup_provider
            owner_name = @class_method_lookup_provider.call(class_name, node.method.to_s)
            if owner_name
              def_node = @method_registry.lookup(owner_name, node.method.to_s)
              if def_node
                return_result = infer(def_node)
                return Result.new(
                  return_result.type,
                  "#{class_name}.#{node.method} (project)",
                  :project
                )
              end
            end
          end

          # Fall back to RBS signature provider
          arg_types = node.args.map { |arg| infer(arg).type }
          return_type = @signature_provider.get_class_method_return_type(
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

          nil
        end

        # Infer type for HashShape field access (hash[:key])
        # @param hash_shape [Types::HashShape] The hash shape type
        # @param key_node [IR::Node] The key argument node
        # @return [Result, nil] The field type result, or nil if not a known symbol key
        def infer_hash_shape_access(hash_shape, key_node)
          # Only handle symbol literal keys
          return nil unless key_node.is_a?(IR::LiteralNode)
          return nil unless key_node.type.is_a?(Types::ClassInstance) && key_node.type.name == "Symbol"
          return nil unless key_node.literal_value.is_a?(Symbol)

          key = key_node.literal_value
          field_type = hash_shape.fields[key]

          if field_type
            Result.new(field_type, "HashShape[:#{key}]", :inference)
          else
            # Key not found in shape - return nil type (like Hash#[] for missing keys)
            Result.new(Types::ClassInstance.new("NilClass"), "HashShape[:#{key}] (missing)", :inference)
          end
        end

        # Resolve called methods to a type
        # First tries external resolver (RubyIndexer), then project methods
        # @param called_methods [Array<Symbol>] Methods called on the parameter
        # @return [Type, nil] Resolved type or nil
        def resolve_called_methods(called_methods)
          return nil if called_methods.empty?

          # First try external resolver (RubyIndexer)
          if @method_list_resolver
            resolved = @method_list_resolver.call(called_methods)
            return resolved if resolved && !resolved.is_a?(Types::Unknown)
          end

          # Then try project methods
          resolve_called_methods_from_project(called_methods.map(&:to_s))
        end

        # Resolve called methods from project method registry
        # Returns ClassInstance if exactly one class matches, Union if 2-3 match, nil otherwise
        # @param methods [Array<String>] Method names
        # @return [Type, nil] Resolved type or nil
        def resolve_called_methods_from_project(methods)
          return nil if methods.empty?

          # Find classes that define all the methods (including inherited ones)
          matching_classes = @method_registry.registered_classes.select do |class_name|
            @method_registry.all_methods_for_class(class_name).superset?(methods.to_set)
          end

          # Filter out subclasses when parent is also matched (prefer most general type)
          matching_classes = filter_to_most_general_types(matching_classes)

          classes_to_type(matching_classes)
        end

        # Filter out classes whose ancestor is also in the list
        # This ensures we return the most general type that satisfies the constraint
        # @param classes [Array<String>] List of class names
        # @return [Array<String>] Filtered list with only the most general types
        def filter_to_most_general_types(classes)
          return classes unless @ancestry_provider

          classes.reject do |class_name|
            ancestors = @ancestry_provider.call(class_name)
            # Check if any ancestor (excluding self) is also in the matching list
            ancestors.any? { |ancestor| ancestor != class_name && classes.include?(ancestor) }
          end
        end

        # Apply type simplification to a result
        # @param result [Result] The inference result
        # @return [Result] Result with simplified type
        def simplify_result(result)
          simplified_type = @type_simplifier.simplify(result.type)
          return result if simplified_type.equal?(result.type)

          Result.new(simplified_type, result.reason, result.source)
        end

        # Build substitutions hash with type variables and self
        # @param receiver_type [Type] The receiver type
        # @return [Hash{Symbol => Type}] Substitutions including :self
        def build_substitutions(receiver_type)
          substitutions = receiver_type.type_variable_substitutions.dup
          substitutions[:self] = receiver_type
          substitutions
        end
      end
    end
  end
end
