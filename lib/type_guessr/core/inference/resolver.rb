# frozen_string_literal: true

require_relative "../ir/nodes"
require_relative "../types"
require_relative "../type_simplifier"
require_relative "../registry/method_registry"
require_relative "../registry/instance_variable_registry"
require_relative "../registry/class_variable_registry"
require_relative "../registry/signature_registry"
require_relative "result"

module TypeGuessr
  module Core
    module Inference
      # Resolves types by traversing the IR dependency graph
      # Each node points to nodes it depends on (reverse dependency graph)
      class Resolver
        # Sentinel value to detect circular references during inference
        INFERRING = Object.new.freeze

        # Maximum recursion depth for type inference.
        # Measured max across project+gem code: 43 (rubygems default_gem_spec chain).
        # Set to 50 to cover all observed cases with margin.
        MAX_DEPTH = 50

        # Method registry for storing and looking up project method definitions
        # @return [Registry::MethodRegistry]
        attr_reader :method_registry

        # Instance variable registry for storing and looking up instance variables
        # @return [Registry::InstanceVariableRegistry]
        attr_reader :ivar_registry

        # Class variable registry for storing and looking up class variables
        # @return [Registry::ClassVariableRegistry]
        attr_reader :cvar_registry

        # @param signature_registry [Registry::SignatureRegistry] Registry for stdlib RBS signatures
        # @param type_simplifier [TypeSimplifier] Type simplifier for normalizing union types
        # @param code_index [#find_classes_defining_methods, #ancestors_of, #constant_kind, #class_method_owner]
        #   Adapter wrapping RubyIndexer
        # @param method_registry [Registry::MethodRegistry] Registry for project methods
        # @param ivar_registry [Registry::InstanceVariableRegistry] Registry for instance variables
        # @param cvar_registry [Registry::ClassVariableRegistry] Registry for class variables
        def initialize(signature_registry, type_simplifier:, code_index:, method_registry:, ivar_registry:, cvar_registry:)
          @signature_registry = signature_registry
          @code_index = code_index
          @method_registry = method_registry
          @ivar_registry = ivar_registry
          @cvar_registry = cvar_registry
          @cache = {}.compare_by_identity
          @type_simplifier = type_simplifier
          @depth = 0
        end

        # Infer the type of an IR node
        # @param node [IR::Node] IR node to infer type for
        # @return [Result] Inference result with type and reason
        def infer(node)
          # Early return: nil node passed (defensive, shouldn't happen in normal flow)
          return Result.new(Types::Unknown.instance, "no node", :unknown) unless node

          # Use cache to avoid redundant inference
          cached = @cache[node]

          # Early return: circular reference detected (A→B→A pattern)
          # INFERRING sentinel means we're already processing this node up the call stack
          return Result.new(Types::Unknown.instance, "circular reference", :unknown) if cached.equal?(INFERRING)

          # Early return: cache hit - return previously computed result
          return cached if cached

          # Early return: depth limit exceeded
          return Result.new(Types::Unknown.instance, "max depth exceeded", :unknown) if @depth >= MAX_DEPTH

          # Mark as in-progress to detect cycles
          @cache[node] = INFERRING

          @depth += 1
          result = infer_node(node)
          @depth -= 1

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
        # @return [Type] The resulting type
        def classes_to_type(classes)
          # Early return: no classes matched the called_methods query
          return Types::Unknown.instance if classes.empty?
          # Early return: single class match - no Union needed
          return Types::ClassInstance.for(classes.first) if classes.size == 1

          types = classes.map { |c| Types::ClassInstance.for(c) }
          union = Types::Union.new(types)
          @type_simplifier.simplify(union)
        end

        private def infer_node(node)
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
          when IR::OrNode
            infer_or(node)
          when IR::MergeNode
            infer_merge(node)
          when IR::DefNode
            infer_def(node)
          when IR::SelfNode
            infer_self(node)
          when IR::NarrowNode
            infer_narrow(node)
          when IR::ReturnNode
            infer_return(node)
          else
            Result.new(Types::Unknown.instance, "unknown node type", :unknown)
          end
        end

        private def infer_literal(node)
          Result.new(node.type, "literal", :literal)
        end

        private def infer_local_write(node)
          # Early return: variable declared but no value assigned (shouldn't happen in valid Ruby)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        private def infer_local_read(node)
          # Early return: variable read without corresponding write (undefined variable)
          return Result.new(Types::Unknown.instance, "unassigned variable", :unknown) unless node.write_node

          write_result = infer(node.write_node)

          # Fallback: write type is Unknown, try called_methods inference
          if write_result.type.is_a?(Types::Unknown) && node.called_methods.any?
            resolved_type = resolve_called_methods(node.called_methods)

            # Early return: called_methods successfully resolved to a type
            if !resolved_type.is_a?(Types::Unknown)
              return Result.new(
                resolved_type,
                "variable inferred from #{node.called_methods.join(", ")}",
                :inference
              )
            end
          end

          write_result
        end

        private def infer_instance_variable_write(node)
          # Early return: @var declared but no value assigned (shouldn't happen in valid Ruby)
          return Result.new(Types::Unknown.instance, "unassigned instance variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        private def infer_instance_variable_read(node)
          write_node = node.write_node

          # Deferred lookup: if write_node is nil at conversion time, try registry
          write_node = @ivar_registry.lookup(node.class_name, node.name) if write_node.nil? && node.class_name

          # Early return: @var write not found (conversion + registry both failed)
          return Result.new(Types::Unknown.instance, "unassigned instance variable", :unknown) unless write_node

          infer(write_node)
        end

        private def infer_class_variable_write(node)
          # Early return: @@var declared but no value assigned (shouldn't happen in valid Ruby)
          return Result.new(Types::Unknown.instance, "unassigned class variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        private def infer_class_variable_read(node)
          write_node = node.write_node

          # Deferred lookup: if write_node is nil at conversion time, try registry
          write_node = @cvar_registry.lookup(node.class_name, node.name) if write_node.nil? && node.class_name

          # Early return: @@var write not found (conversion + registry both failed)
          return Result.new(Types::Unknown.instance, "unassigned class variable", :unknown) unless write_node

          infer(write_node)
        end

        private def infer_param(node)
          # Early returns for special parameter kinds (type is known structurally)
          case node.kind
          when :rest
            # Early return: *args is always Array
            return Result.new(Types::ArrayType.new, "rest parameter", :inference)
          when :keyword_rest
            # Early return: **kwargs is always Hash
            return Result.new(Types::ClassInstance.for("Hash"), "keyword rest parameter", :inference)
          when :block
            # Early return: &block is always Proc
            return Result.new(Types::ClassInstance.for("Proc"), "block parameter", :inference)
          when :forwarding
            # Early return: ... forwards all arguments
            return Result.new(Types::ForwardingArgs.instance, "forwarding parameter", :inference)
          end

          # Early return: optional parameter with default value - infer from default
          if node.default_value
            dep_result = infer(node.default_value)
            return Result.new(dep_result.type, "parameter default: #{dep_result.reason}", dep_result.source)
          end

          # Fallback: try to resolve type from called methods
          if node.called_methods.any?
            resolved_type = resolve_called_methods(node.called_methods)

            # Early return: called_methods query found no matching classes
            if resolved_type.is_a?(Types::Unknown)
              return Result.new(
                Types::Unknown.instance,
                "parameter with unresolved methods: #{node.called_methods.join(", ")}",
                :unknown
              )
            # Early return: called_methods successfully resolved to a type
            else
              return Result.new(
                resolved_type,
                "parameter inferred from #{node.called_methods.join(", ")}",
                :project
              )
            end
          end

          Result.new(Types::Unknown.instance, "parameter without type info", :unknown)
        end

        private def infer_constant(node)
          # Early return: constant assignment (Foo = ...) - infer from assigned value
          if node.dependency
            dep_result = infer(node.dependency)
            return Result.new(dep_result.type, "constant #{node.name}: #{dep_result.reason}", dep_result.source)
          end

          # Check if constant is a class or module using code_index adapter
          kind = @code_index&.constant_kind(node.name)

          # Early return: class/module constant - return singleton type
          if %i[class module].include?(kind)
            return Result.new(
              Types::SingletonType.new(node.name),
              "class constant #{node.name}",
              :inference
            )
          end

          Result.new(Types::Unknown.instance, "undefined constant", :unknown)
        end

        private def infer_call(node)
          # Special case: Class method calls (ClassName.method)
          if node.receiver.is_a?(IR::ConstantNode)
            # Resolve constant first (handles aliases like RecipeAlias = Recipe)
            receiver_result = infer(node.receiver)
            class_name = case receiver_result.type
                         when Types::SingletonType then receiver_result.type.name
                         else node.receiver.name
                         end

            result = infer_class_method_call(class_name, node)
            # Early return: ClassName.method resolved successfully
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
              # Early return: singleton.method resolved successfully
              return result if result
            when Types::ClassInstance
              # 1. Try project methods first
              def_node = @method_registry.lookup(receiver_type.name, node.method.to_s)
              # Early return: project method found - use project inference
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
              return_type = @signature_registry.get_method_return_type(
                receiver_type.name,
                node.method.to_s,
                arg_types
              )

              # Fall back to Object if class-specific lookup returns Unknown
              if return_type.is_a?(Types::Unknown) && receiver_type.name != "Object"
                return_type = @signature_registry.get_method_return_type(
                  "Object",
                  node.method.to_s,
                  arg_types
                )
              end

              # Substitute self and block return type with receiver type
              substitutions = { self: receiver_type }
              add_block_return_substitution(substitutions, node)
              return_type = return_type.substitute(substitutions)

              # Early return: ClassInstance RBS lookup (may be Unknown if not found)
              return Result.new(
                return_type,
                "#{receiver_type.name}##{node.method}",
                :stdlib
              )
            when Types::ArrayType
              # Handle Array methods with element type substitution
              substitutions = build_substitutions(receiver_type)

              add_block_return_substitution(substitutions, node)

              # Get raw return type, then substitute type variables
              raw_return_type = @signature_registry.get_method_return_type("Array", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              # Early return: ArrayType RBS lookup with type variable substitution
              return Result.new(
                return_type,
                "Array[#{receiver_type.element_type || "untyped"}]##{node.method}",
                :stdlib
              )
            when Types::TupleType
              # Handle indexed access with integer literal
              if node.method == :[] && node.args.size == 1
                tuple_result = infer_tuple_access(receiver_type, node.args.first)
                return tuple_result if tuple_result
              end

              # Fall back to Array RBS for other methods
              substitutions = build_substitutions(receiver_type)
              add_block_return_substitution(substitutions, node)
              raw_return_type = @signature_registry.get_method_return_type("Array", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "[#{receiver_type.element_types.join(", ")}]##{node.method}",
                :stdlib
              )
            when Types::HashShape
              # Handle HashShape field access with [] method
              if node.method == :[] && node.args.size == 1
                key_result = infer_hash_shape_access(receiver_type, node.args.first)
                # Early return: hash[:key] with known symbol key resolved to field type
                return key_result if key_result
              end

              # Fall back to Hash RBS for other methods
              substitutions = build_substitutions(receiver_type)
              add_block_return_substitution(substitutions, node)
              raw_return_type = @signature_registry.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              # Early return: HashShape RBS lookup for non-[] methods
              return Result.new(
                return_type,
                "HashShape##{node.method}",
                :stdlib
              )
            when Types::HashType
              # Handle generic HashType
              substitutions = build_substitutions(receiver_type)
              add_block_return_substitution(substitutions, node)
              raw_return_type = @signature_registry.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              # Early return: HashType RBS lookup with type variable substitution
              return Result.new(
                return_type,
                "Hash[#{receiver_type.key_type}, #{receiver_type.value_type}]##{node.method}",
                :stdlib
              )
            end

            # Fallback: try to infer Unknown receiver type from method uniqueness
            if receiver_type.is_a?(Types::Unknown)
              # Create CalledMethod with nil positional_count to skip signature matching
              cm = IR::CalledMethod.new(name: node.method, positional_count: nil, keywords: [])
              inferred_receiver = resolve_called_methods([cm])
              if inferred_receiver.is_a?(Types::ClassInstance)
                # Try project methods with inferred receiver type
                def_node = @method_registry.lookup(inferred_receiver.name, node.method.to_s)
                # Early return: inferred receiver → project method found
                if def_node
                  return_result = infer(def_node)
                  return Result.new(
                    return_result.type,
                    "#{inferred_receiver.name}##{node.method} (inferred receiver)",
                    :project
                  )
                end

                # Early return: inferred receiver → RBS lookup
                arg_types = node.args.map { |arg| infer(arg).type }
                return_type = @signature_registry.get_method_return_type(
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

          # Fallback: method call without receiver or unknown receiver type
          # First, try to lookup top-level method
          def_node = @method_registry.lookup("", node.method.to_s)
          # Early return: top-level project method found
          if def_node
            return_type = infer(def_node.return_node)
            return Result.new(return_type.type, "top-level method #{node.method}", :project)
          end

          # Fallback to Object to query RBS for common methods (==, to_s, etc.)
          arg_types = node.args.map { |arg| infer(arg).type }
          return_type = @signature_registry.get_method_return_type("Object", node.method.to_s, arg_types)
          # Substitute self with receiver type if available (e.g., Object#dup returns self)
          return_type = return_type.substitute({ self: receiver_type }) if receiver_type
          # Early return: Object common method found in RBS
          return Result.new(return_type, "Object##{node.method}", :stdlib) unless return_type.is_a?(Types::Unknown)

          Result.new(Types::Unknown.instance, "call #{node.method} on unknown receiver", :unknown)
        end

        private def infer_block_param_slot(node)
          # Early return: top-level block (each { } without receiver class context)
          return Result.new(Types::Unknown.instance, "block param without type info", :unknown) unless node.call_node.receiver

          receiver_type = infer(node.call_node.receiver).type
          class_name = receiver_type.rbs_class_name

          # Path 1: RBS-based inference (when receiver type has a class name)
          if class_name
            raw_block_param_types = @signature_registry.get_block_param_types(class_name, node.call_node.method.to_s)

            if raw_block_param_types.empty? && class_name != "Object"
              raw_block_param_types = @signature_registry.get_block_param_types("Object", node.call_node.method.to_s)
            end

            if raw_block_param_types.size > node.index
              raw_type = raw_block_param_types[node.index]
              resolved_type = raw_type.substitute(build_substitutions(receiver_type))
              return Result.new(resolved_type, "block param from #{class_name}##{node.call_node.method}", :stdlib)
            end
          end

          # Path 2: Fallback to called_methods inference (like infer_param)
          if node.called_methods.any?
            resolved_type = resolve_called_methods(node.called_methods)

            if resolved_type.is_a?(Types::Unknown)
              return Result.new(
                Types::Unknown.instance,
                "block param with unresolved methods: #{node.called_methods.join(", ")}",
                :unknown
              )
            end

            return Result.new(
              resolved_type,
              "block param inferred from #{node.called_methods.join(", ")}",
              :project
            )
          end

          Result.new(Types::Unknown.instance, "block param without type info", :unknown)
        end

        private def infer_merge(node)
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

        private def infer_or(node)
          lhs_result = infer(node.lhs)
          rhs_result = infer(node.rhs)
          lhs_type = lhs_result.type

          # Separate LHS into truthy and falsy parts
          truthy_lhs = remove_falsy_types(lhs_type)
          has_falsy = falsy_types?(lhs_type)

          if !has_falsy
            # LHS is always truthy → RHS unreachable
            Result.new(lhs_type, "or: #{lhs_result.reason} (always truthy)", lhs_result.source)
          elsif truthy_lhs.is_a?(Types::Unknown)
            # LHS is entirely falsy → RHS only
            Result.new(rhs_result.type, "or: #{rhs_result.reason} (lhs falsy)", rhs_result.source)
          else
            # Mixed: truthy part of LHS | RHS
            union = Types::Union.new([truthy_lhs, rhs_result.type])
            Result.new(union, "or: #{lhs_result.reason} | #{rhs_result.reason}", :unknown)
          end
        end

        private def remove_falsy_types(type)
          case type
          when Types::Union
            truthy = type.types.reject { |t| falsy_type?(t) }
            case truthy.size
            when 0 then Types::Unknown.instance
            when 1 then truthy.first
            else Types::Union.new(truthy)
            end
          else
            falsy_type?(type) ? Types::Unknown.instance : type
          end
        end

        private def falsy_types?(type)
          case type
          when Types::Union
            type.types.any? { |t| falsy_type?(t) }
          else
            falsy_type?(type)
          end
        end

        private def falsy_type?(type)
          type.is_a?(Types::ClassInstance) && %w[NilClass FalseClass].include?(type.name)
        end

        private def infer_def(node)
          # Early return: initialize always returns self (Ruby semantics)
          if node.name == :initialize && node.class_name
            return Result.new(
              Types::SelfType.instance,
              "def #{node.name} returns self",
              :project
            )
          end

          # Early return: empty method body returns nil (Ruby semantics)
          unless node.return_node
            return Result.new(
              Types::ClassInstance.for("NilClass"),
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

        private def infer_self(node)
          type = if node.singleton
                   Types::SingletonType.new(node.class_name)
                 else
                   Types::ClassInstance.for(node.class_name)
                 end
          Result.new(type, "self in #{node.class_name}", :inference)
        end

        private def infer_narrow(node)
          inner_result = infer(node.value)
          narrowed_type = case node.kind
                          when :truthy then remove_falsy_types(inner_result.type)
                          else inner_result.type
                          end
          Result.new(narrowed_type, "narrowed(#{inner_result.reason})", inner_result.source)
        end

        private def infer_return(node)
          # Early return: `return expr` - infer from expression
          if node.value
            value_result = infer(node.value)
            return Result.new(value_result.type, "explicit return: #{value_result.reason}", value_result.source)
          end

          # Default: bare `return` returns nil
          Result.new(Types::ClassInstance.for("NilClass"), "explicit return nil", :inference)
        end

        # Infer class method call (ClassName.method or self.method in singleton context)
        # @param class_name [String] The class name
        # @param node [IR::CallNode] The call node
        # @return [Result, nil] The result if resolved, nil otherwise (caller handles fallback)
        private def infer_class_method_call(class_name, node)
          # Early return: Foo.new always returns Foo instance
          if node.method == :new
            return Result.new(
              Types::ClassInstance.for(class_name),
              "#{class_name}.new",
              :inference
            )
          end

          # Try project class methods first (includes extended module methods)
          # Use code_index adapter to find method owner
          owner_name = @code_index&.class_method_owner(class_name, node.method.to_s)

          # Early return: project class method found
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

          # Fall back to RBS signature provider
          arg_types = node.args.map { |arg| infer(arg).type }
          return_type = @signature_registry.get_class_method_return_type(
            class_name,
            node.method.to_s,
            arg_types
          )

          # Early return: RBS class method found
          unless return_type.is_a?(Types::Unknown)
            return Result.new(
              return_type,
              "#{class_name}.#{node.method} (RBS)",
              :rbs
            )
          end

          # Return nil to let caller try other fallback strategies
          nil
        end

        # Infer type for HashShape field access (hash[:key])
        # @param hash_shape [Types::HashShape] The hash shape type
        # @param key_node [IR::Node] The key argument node
        # @return [Result, nil] The field type result, or nil if not a known symbol key (caller falls back to Hash RBS)
        private def infer_hash_shape_access(hash_shape, key_node)
          # Early return nil: dynamic key (hash[var]) - can't resolve at static analysis time
          return nil unless key_node.is_a?(IR::LiteralNode)
          # Early return nil: non-symbol key (hash["key"]) - HashShape only tracks symbol keys
          return nil unless key_node.type.is_a?(Types::ClassInstance) && key_node.type.name == "Symbol"
          # Early return nil: literal_value not Symbol (defensive)
          return nil unless key_node.literal_value.is_a?(Symbol)

          key = key_node.literal_value
          field_type = hash_shape.fields[key]

          # Early return: known field found in shape
          return Result.new(field_type, "HashShape[:#{key}]", :inference) if field_type

          # Default: key not found in shape - return nil type (like Hash#[] for missing keys)
          Result.new(Types::ClassInstance.for("NilClass"), "HashShape[:#{key}] (missing)", :inference)
        end

        # Infer type for TupleType indexed access (tuple[0])
        # @param tuple_type [Types::TupleType] The tuple type
        # @param index_node [IR::Node] The index argument node
        # @return [Result, nil] The element type result, or nil if not an integer literal (caller falls back to Array RBS)
        private def infer_tuple_access(tuple_type, index_node)
          return nil unless index_node.is_a?(IR::LiteralNode)
          return nil unless index_node.type.is_a?(Types::ClassInstance) && index_node.type.name == "Integer"
          return nil unless index_node.literal_value.is_a?(Integer)

          index = index_node.literal_value
          # Support negative indexing
          index = tuple_type.element_types.size + index if index.negative?

          element_type = tuple_type.element_types[index]
          return Result.new(element_type, "Tuple[#{index}]", :inference) if element_type

          Result.new(Types::ClassInstance.for("NilClass"), "Tuple[#{index}] (out of range)", :inference)
        end

        # Resolve called methods to a type via code_index adapter
        # @param called_methods [Array<CalledMethod>] List of called methods
        # @return [Type] The resulting type
        private def resolve_called_methods(called_methods)
          # Early return: no method call info available for inference
          return Types::Unknown.instance if called_methods.empty?

          classes = @code_index.find_classes_defining_methods(called_methods)
          classes_to_type(classes)
        end

        # Apply type simplification to a result
        # @param result [Result] The inference result
        # @return [Result] Result with simplified type
        private def simplify_result(result)
          simplified_type = @type_simplifier.simplify(result.type)
          return result if simplified_type.equal?(result.type)

          Result.new(simplified_type, result.reason, result.source)
        end

        # Add block return type substitution (:U) to substitutions hash
        # @param substitutions [Hash{Symbol => Type}] Substitutions hash to modify
        # @param node [IR::CallNode] The call node with block info
        # @return [void]
        private def add_block_return_substitution(substitutions, node)
          return unless node.has_block

          if node.block_body
            block_result = infer(node.block_body)
            substitutions[:U] = block_result.type unless block_result.type.is_a?(Types::Unknown)
          else
            # Empty block returns nil
            substitutions[:U] = Types::ClassInstance.for("NilClass")
          end
        end

        # Build substitutions hash with type variables and self
        # @param receiver_type [Type] The receiver type
        # @return [Hash{Symbol => Type}] Substitutions including :self
        private def build_substitutions(receiver_type)
          substitutions = receiver_type.type_variable_substitutions.dup
          substitutions[:self] = receiver_type
          substitutions
        end
      end
    end
  end
end
