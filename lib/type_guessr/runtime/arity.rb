# frozen_string_literal: true

module TypeGuessr
  module Runtime
    # Call-site arity checking against live reflection.
    #
    # Loaded by server.rb inside the *target project's* process, so it must stay
    # dependency-free (no requires, no other TypeGuessr files).
    module Arity
      # Can `method_name` on `klass` be called with this argument shape?
      #
      # @param klass [Module]
      # @param method_name [Symbol]
      # @param singleton [Boolean] check the class object instead of its instances
      # @param positional_count [Integer, nil] nil when the call site uses a splat (unknown)
      # @param keywords [Array<Symbol, String>] keyword names passed at the call site
      # @return [Boolean] false only when the call provably cannot bind
      def self.accepts_arity?(klass, method_name, singleton, positional_count, keywords)
        keywords = (keywords || []).map(&:to_sym)
        return true if positional_count.nil? && keywords.empty?

        meth = singleton ? klass.method(method_name) : klass.instance_method(method_name)

        required = 0
        optional = 0
        rest = false
        keyrest = false
        key_names = []

        meth.parameters.each do |kind, name|
          case kind
          when :req then required += 1
          when :opt then optional += 1
          when :rest then rest = true
          when :key, :keyreq then key_names << name
          when :keyrest then keyrest = true
          end
        end

        keyword_params = !key_names.empty? || keyrest

        # A method with no keyword parameters receives the call's keywords as one
        # trailing Hash positional argument.
        effective = positional_count
        effective += 1 if effective && keywords.any? && !keyword_params

        return false if effective && !(rest || effective.between?(required, required + optional))

        # Only reject unknown keyword names. Missing required keywords are not
        # checked: the call site may forward them through a splat or **opts.
        return false if keywords.any? && keyword_params && !keyrest && !keywords.all? { |k| key_names.include?(k) }

        true
      rescue NameError
        # Reflection could not find the method (private, removed, refinement, ...)
        true
      end
    end
  end
end
