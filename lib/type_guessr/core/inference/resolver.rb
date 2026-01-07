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

        # Callback for getting class ancestors
        # @return [Proc, nil] A proc that takes class_name and returns array of ancestor names
        attr_accessor :ancestry_provider

        # Callback for checking if a constant is a class or module
        # @return [Proc, nil] A proc that takes constant_name and returns :class, :module, or nil
        attr_accessor :constant_kind_provider

        # Callback for looking up class methods via RubyIndexer
        # @return [Proc, nil] A proc that takes (class_name, method_name) and returns owner_name or nil
        attr_accessor :class_method_lookup_provider

        def initialize(signature_provider)
          @signature_provider = signature_provider
          @cache = {}.compare_by_identity
          @project_methods = {} # { "ClassName" => { "method_name" => DefNode } }
          @instance_variables = {} # { "ClassName" => { :@name => InstanceVariableWriteNode } }
          @class_variables = {} # { "ClassName" => { :@@name => ClassVariableWriteNode } }
          @project_classes = {} # { "ClassName" => :class or :module }
          @duck_type_resolver = nil
          @ancestry_provider = nil
          @constant_kind_provider = nil
          @class_method_lookup_provider = nil
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
          # Try current class first
          result = @project_methods.dig(class_name, method_name)
          return result if result

          # Traverse ancestor chain if provider available
          return nil unless @ancestry_provider

          ancestors = @ancestry_provider.call(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @project_methods.dig(ancestor_name, method_name)
            return result if result
          end

          nil
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

        # Register an instance variable write for deferred lookup
        # @param class_name [String] Class name
        # @param name [Symbol] Instance variable name (e.g., :@recipe)
        # @param write_node [IR::InstanceVariableWriteNode] Write node
        def register_instance_variable(class_name, name, write_node)
          return unless class_name

          @instance_variables[class_name] ||= {}
          # First write wins (preserves consistent behavior)
          @instance_variables[class_name][name] ||= write_node
        end

        # Look up an instance variable write from the registry
        # @param class_name [String] Class name
        # @param name [Symbol] Instance variable name
        # @return [IR::InstanceVariableWriteNode, nil]
        def lookup_instance_variable(class_name, name)
          return nil unless class_name

          # Try current class first
          result = @instance_variables.dig(class_name, name)
          return result if result

          # Traverse ancestor chain if provider available
          return nil unless @ancestry_provider

          ancestors = @ancestry_provider.call(class_name)
          ancestors.each do |ancestor_name|
            next if ancestor_name == class_name # Skip self

            result = @instance_variables.dig(ancestor_name, name)
            return result if result
          end

          nil
        end

        # Register a class variable write for deferred lookup
        # @param class_name [String] Class name
        # @param name [Symbol] Class variable name (e.g., :@@count)
        # @param write_node [IR::ClassVariableWriteNode] Write node
        def register_class_variable(class_name, name, write_node)
          return unless class_name

          @class_variables[class_name] ||= {}
          @class_variables[class_name][name] ||= write_node
        end

        # Look up a class variable write from the registry
        # @param class_name [String] Class name
        # @param name [Symbol] Class variable name
        # @return [IR::ClassVariableWriteNode, nil]
        def lookup_class_variable(class_name, name)
          @class_variables.dig(class_name, name)
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

          infer(node.write_node)
        end

        def infer_instance_variable_write(node)
          return Result.new(Types::Unknown.instance, "unassigned instance variable", :unknown) unless node.value

          dep_result = infer(node.value)
          Result.new(dep_result.type, "assigned from #{dep_result.reason}", dep_result.source)
        end

        def infer_instance_variable_read(node)
          write_node = node.write_node

          # Deferred lookup: if write_node is nil at conversion time, try registry
          write_node = lookup_instance_variable(node.class_name, node.name) if write_node.nil? && node.class_name

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
          write_node = lookup_class_variable(node.class_name, node.name) if write_node.nil? && node.class_name

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
            class_name = node.receiver.name

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
                # Look up method from owner (module or singleton class)
                def_node = lookup_method(owner_name, node.method.to_s)
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

            # Query for method return type: project first, then RBS
            case receiver_type
            when Types::ClassInstance
              # 1. Try project methods first
              def_node = lookup_method(receiver_type.name, node.method.to_s)
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

              return Result.new(
                return_type,
                "#{receiver_type.name}##{node.method}",
                :stdlib
              )
            when Types::ArrayType
              # Handle Array methods with element type substitution
              # Start with substitutions from receiver type (e.g., Elem)
              substitutions = receiver_type.type_variable_substitutions.dup

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
              substitutions = receiver_type.type_variable_substitutions
              raw_return_type = @signature_provider.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "HashShape##{node.method}",
                :stdlib
              )
            when Types::HashType
              # Handle generic HashType
              substitutions = receiver_type.type_variable_substitutions
              raw_return_type = @signature_provider.get_method_return_type("Hash", node.method.to_s)
              return_type = raw_return_type.substitute(substitutions)
              return Result.new(
                return_type,
                "Hash[#{receiver_type.key_type}, #{receiver_type.value_type}]##{node.method}",
                :stdlib
              )
            end
          end

          # Method call without receiver or unknown receiver type
          # First, try to lookup top-level method
          def_node = lookup_method("", node.method.to_s)
          if def_node
            return_type = infer(def_node.return_node)
            return Result.new(return_type.type, "top-level method #{node.method}", :project)
          end

          # Fallback to Object to query RBS for common methods (==, to_s, etc.)
          arg_types = node.args.map { |arg| infer(arg).type }
          return_type = @signature_provider.get_method_return_type("Object", node.method.to_s, arg_types)
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
          return Result.new(Types::Unknown.instance, "block param without type info", :unknown) unless raw_block_param_types.size > node.index

          # Type#substitute applies type variable substitutions
          raw_type = raw_block_param_types[node.index]
          resolved_type = raw_type.substitute(receiver_type.type_variable_substitutions)

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

        # Resolve DuckType to ClassInstance using registered project methods
        # Returns ClassInstance if exactly one class matches, Union if 2-3 match, nil otherwise
        def resolve_duck_type_from_project_methods(duck_type)
          methods = duck_type.methods.map(&:to_s)
          return nil if methods.empty?

          # Find classes that define all the methods (including inherited ones)
          matching_classes = @project_methods.keys.select do |class_name|
            all_methods_for_class(class_name).superset?(methods.to_set)
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

        # Get all methods available on a class (including inherited methods from project)
        # @param class_name [String] Class name
        # @return [Set<String>] Set of method names
        def all_methods_for_class(class_name)
          # Start with directly defined methods
          class_methods = (@project_methods[class_name]&.keys || []).to_set

          # Add inherited methods if ancestry_provider is available
          if @ancestry_provider
            ancestors = @ancestry_provider.call(class_name)
            ancestors.each do |ancestor_name|
              next if ancestor_name == class_name # Skip self

              ancestor_methods = @project_methods[ancestor_name]&.keys || []
              class_methods.merge(ancestor_methods)
            end
          end

          class_methods
        end
      end
    end
  end
end
