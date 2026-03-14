# frozen_string_literal: true

class Comment
  include Mongoid::Document

  field :body, type: String
  field :author_name, type: String

  # Embedded in parent
  embedded_in :article
end
