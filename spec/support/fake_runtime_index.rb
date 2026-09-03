# frozen_string_literal: true

require "type_guessr/runtime/arity"
require_relative "inference_helper"

# Fake runtime index for specs that need method-existence answers.
#
# `defined_methods` maps a receiver key to the method names it answers:
#   "User"  → instance methods, "User." → singleton (class) methods.
# A class absent from the table is unknown to the runtime (method_defined? → nil).
#
# `reflected` maps a name to a real Ruby class or module, which then answers
# existence, arity (through the same code the server runs) and constant kind.
class FakeRuntimeIndex < InferenceHelper::StubIndexAdapter
  attr_reader :queries

  def initialize(defined_methods: {}, known_constants: [], reflected: {})
    super()
    @defined_methods = defined_methods
    @known_constants = known_constants
    @reflected = reflected
    @queries = []
  end

  def constant_kind(name)
    mod = @reflected[name]
    return mod.is_a?(Class) ? :class : :module if mod

    @known_constants.include?(name) ? :class : nil
  end

  def method_defined?(class_name, method_name, singleton: false, positional_count: nil, keywords: [])
    @queries << [class_name, method_name, singleton, positional_count, keywords]

    mod = @reflected[class_name]
    return reflect(mod, method_name, singleton, positional_count, keywords) if mod

    @defined_methods[singleton ? "#{class_name}." : class_name]&.include?(method_name)
  end

  private def reflect(mod, method_name, singleton, positional_count, keywords)
    name = method_name.to_sym
    return false unless singleton ? mod.respond_to?(name) : mod.method_defined?(name)
    return true if TypeGuessr::Runtime::Arity.accepts_arity?(mod, name, singleton, positional_count, keywords)

    "arity"
  end
end
