# frozen_string_literal: true

class Metadata
  include Mongoid::Document

  field :key, type: String
  field :value, type: String

  # Embedded in parent
  embedded_in :article
end
