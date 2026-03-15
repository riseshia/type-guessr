# frozen_string_literal: true

require_relative "../../../type_guessr/core/types"

module RubyLsp
  module TypeGuessr
    module Dsl
      # Maps ActiveRecord column type strings to TypeGuessr Types.
      # Pure mapping with no external dependencies.
      # AR-specific: Mongoid provides Ruby types directly in field declarations.
      module ArTypeMapper
        def self.map(ar_type, nullable: true)
          base = case ar_type.to_s
                 when "string", "text"
                   ::TypeGuessr::Core::Types::ClassInstance.for("String")
                 when "integer", "bigint"
                   ::TypeGuessr::Core::Types::ClassInstance.for("Integer")
                 when "boolean"
                   ::TypeGuessr::Core::Types::Union.new([
                                                          ::TypeGuessr::Core::Types::ClassInstance.for("TrueClass"),
                                                          ::TypeGuessr::Core::Types::ClassInstance.for("FalseClass"),
                                                        ])
                 when "float"
                   ::TypeGuessr::Core::Types::ClassInstance.for("Float")
                 when "decimal"
                   ::TypeGuessr::Core::Types::ClassInstance.for("BigDecimal")
                 when "date"
                   ::TypeGuessr::Core::Types::ClassInstance.for("Date")
                 when "datetime", "timestamp"
                   ::TypeGuessr::Core::Types::ClassInstance.for("ActiveSupport::TimeWithZone")
                 when "json", "jsonb"
                   ::TypeGuessr::Core::Types::ClassInstance.for("Hash")
                 else
                   ::TypeGuessr::Core::Types::Unknown.instance
                 end

          if nullable && !base.is_a?(::TypeGuessr::Core::Types::Unknown)
            nil_type = ::TypeGuessr::Core::Types::ClassInstance.for("NilClass")
            if base.is_a?(::TypeGuessr::Core::Types::Union)
              ::TypeGuessr::Core::Types::Union.new(base.types + [nil_type])
            else
              ::TypeGuessr::Core::Types::Union.new([base, nil_type])
            end
          else
            base
          end
        end
      end
    end
  end
end
