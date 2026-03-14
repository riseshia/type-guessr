# frozen_string_literal: true

class Post < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :comments, as: :commentable
  has_many :taggings
  has_many :tags, through: :taggings

  # Nested attributes
  accepts_nested_attributes_for :comments, allow_destroy: true

  # Enum
  enum :status, { draft: 0, published: 1, archived: 2 }

  # Scopes
  scope :published, -> { where(published: true) }
  scope :recent, -> { order(created_at: :desc) }

  # Delegate
  delegate :name, to: :user, prefix: :author
end
