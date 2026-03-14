# frozen_string_literal: true

class Profile < ApplicationRecord
  # Associations
  belongs_to :user

  # Store accessor (JSON column)
  store_accessor :settings, :theme, :language, :notifications_enabled
end
