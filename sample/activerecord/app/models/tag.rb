# frozen_string_literal: true

class Tag < ApplicationRecord
  # HABTM association
  has_and_belongs_to_many :posts
end
