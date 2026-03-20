# frozen_string_literal: true

require_relative "../ir"

module TypeGuessr
  module Core
    module Converter
      class PrismConverter
        # Context for tracking variable bindings during conversion
        class Context
          attr_reader :variables, :file_path, :location_index, :method_registry, :ivar_registry, :cvar_registry
          attr_accessor :current_class, :current_method, :in_singleton_method

          def initialize(parent = nil, file_path: nil, location_index: nil,
                         method_registry: nil, ivar_registry: nil, cvar_registry: nil)
            @parent = parent
            @variables = {} # name => node
            @instance_variables = {} # @name => node (only for class-level context)
            @narrowed_ivars = {} # @name => narrowed node (method-level, does not pollute class-level)
            @constants = {} # name => dependency node (for constant alias tracking)
            @scope_type = nil # :class, :method, :block, :top_level
            @current_class = nil
            @current_method = nil
            @in_singleton_method = false

            # Index/registry references (inherited from parent or set directly)
            @file_path = file_path || parent&.file_path
            @location_index = location_index || parent&.location_index
            @method_registry = method_registry || parent&.method_registry
            @ivar_registry = ivar_registry || parent&.ivar_registry
            @cvar_registry = cvar_registry || parent&.cvar_registry
          end

          def register_variable(name, node)
            @variables[name] = node
          end

          def lookup_variable(name)
            @variables[name] || @parent&.lookup_variable(name)
          end

          # Register an instance variable at the class level
          # Instance variables are shared across all methods in a class
          def register_instance_variable(name, node)
            if @scope_type == :class
              @instance_variables[name] = node
            elsif @parent
              @parent.register_instance_variable(name, node)
            else
              # Top-level instance variable, store locally
              @instance_variables[name] = node
            end
          end

          # Narrow an instance variable's type within the current method scope
          # Does not pollute the class-level ivar definition
          def narrow_instance_variable(name, node)
            @narrowed_ivars[name] = node
          end

          # Lookup an instance variable, checking narrowed ivars first
          def lookup_instance_variable(name)
            return @narrowed_ivars[name] if @narrowed_ivars.key?(name)

            if @scope_type == :class
              @instance_variables[name]
            elsif @parent
              @parent.lookup_instance_variable(name)
            else
              @instance_variables[name]
            end
          end

          # Register a constant's dependency node for alias tracking
          def register_constant(name, dependency_node)
            @constants[name] = dependency_node
          end

          # Lookup a constant's dependency node (for alias resolution)
          def lookup_constant(name)
            @constants[name] || @parent&.lookup_constant(name)
          end

          def fork(scope_type)
            child = Context.new(self)
            child.instance_variable_set(:@scope_type, scope_type)
            child.current_class = current_class_name
            child.current_method = current_method_name
            child.in_singleton_method = @in_singleton_method
            child
          end

          def scope_type
            @scope_type || @parent&.scope_type
          end

          # Get the current class name (from this context or parent)
          def current_class_name
            @current_class || @parent&.current_class_name
          end

          # Get the current method name (from this context or parent)
          def current_method_name
            @current_method || @parent&.current_method_name
          end

          # Generate scope_id for node lookup (e.g., "User#save" or "User" or "")
          # For singleton methods, uses "<Class:ClassName>" format to match RubyIndexer convention
          def scope_id
            base_class_path = current_class_name || ""
            class_path = if @in_singleton_method
                           # Singleton methods use "<Class:ClassName>" suffix
                           parent_name = IR.extract_last_name(base_class_path) || "Object"
                           base_class_path.empty? ? "<Class:Object>" : "#{base_class_path}::<Class:#{parent_name}>"
                         else
                           base_class_path
                         end
            method_name = current_method_name
            if method_name
              "#{class_path}##{method_name}"
            else
              class_path
            end
          end

          # Check if a variable is defined in this context (not inherited from parent)
          def owns_variable?(name)
            @variables.key?(name)
          end

          # Register a variable in the parent context (for block mutation propagation)
          def register_variable_in_parent(name, node)
            @parent&.register_variable(name, node)
          end

          # Get variables that were defined/modified in this context (not from parent)
          def local_variables
            @variables.keys
          end
        end
      end
    end
  end
end
