# frozen_string_literal: true

class Category
  include Mongoid::Document

  field :name, type: String

  # HABTM
  has_and_belongs_to_many :articles
end
