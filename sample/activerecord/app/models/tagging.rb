# frozen_string_literal: true

class Tagging < ApplicationRecord
  # Join model for has_many :through
  belongs_to :post
  belongs_to :tag
end
