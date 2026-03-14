# frozen_string_literal: true

class Address
  include Mongoid::Document

  field :street, type: String
  field :city, type: String
  field :zip, type: String

  # Embedded in parent
  embedded_in :author
end
