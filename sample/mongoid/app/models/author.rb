# frozen_string_literal: true

class Author
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :email, type: String
  field :age, type: Integer
  field :active, type: Boolean

  # Referenced association
  has_many :articles

  # Embedded association
  embeds_one :address
end
