# frozen_string_literal: true

class Review
  include Mongoid::Document

  field :body, type: String
  field :rating, type: Integer
  field :approved, type: Boolean

  # Referenced association
  belongs_to :article
end
