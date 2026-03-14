# frozen_string_literal: true

class Comment < ApplicationRecord
  # Associations
  belongs_to :commentable, polymorphic: true
  belongs_to :user

  # Delegated type
  delegated_type :entryable, types: %w[Message Bulletin]
end
