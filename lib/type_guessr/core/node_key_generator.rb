# frozen_string_literal: true

module TypeGuessr
  module Core
    # Generates unique node keys for IR nodes and Prism node lookups.
    # Single source of truth for node key format to ensure consistency
    # between IR node generation and hover/type inference lookups.
    module NodeKeyGenerator
      module_function

      def local_write(name, offset) = "local_write:#{name}:#{offset}"
      def local_read(name, offset) = "local_read:#{name}:#{offset}"
      def ivar_write(name, offset) = "ivar_write:#{name}:#{offset}"
      def ivar_read(name, offset) = "ivar_read:#{name}:#{offset}"
      def cvar_write(name, offset) = "cvar_write:#{name}:#{offset}"
      def cvar_read(name, offset) = "cvar_read:#{name}:#{offset}"
      def global_write(name, offset) = "global_write:#{name}:#{offset}"
      def global_read(name, offset) = "global_read:#{name}:#{offset}"
      def param(name, offset) = "param:#{name}:#{offset}"
      def bparam(index, offset) = "bparam:#{index}:#{offset}"
      def call(method, offset) = "call:#{method}:#{offset}"
      def def_node(name, offset) = "def:#{name}:#{offset}"
      def self_node(class_name, offset) = "self:#{class_name}:#{offset}"
      def return_node(offset) = "return:#{offset}"
      def merge(offset) = "merge:#{offset}"
      def literal(type_name, offset) = "lit:#{type_name}:#{offset}"
      def constant(name, offset) = "const:#{name}:#{offset}"
      def class_module(name, offset) = "class:#{name}:#{offset}"
    end
  end
end
