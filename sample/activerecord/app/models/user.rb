# frozen_string_literal: true

class User < ApplicationRecord
  # Associations
  has_many :posts
  has_many :comments
  has_one :profile

  # Enum
  enum :role, { member: 0, admin: 1, moderator: 2 }

  # Secure password (requires password_digest column)
  has_secure_password

  # Scopes
  scope :active, -> { where(active: true) }
  scope :adults, -> { where("age >= ?", 18) }
end
