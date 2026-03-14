# frozen_string_literal: true

class Article
  include Mongoid::Document
  include Mongoid::Timestamps

  # Various field types
  field :title, type: String
  field :body, type: String
  field :view_count, type: Integer
  field :rating, type: Float
  field :published, type: Boolean
  field :published_at, type: Time
  field :tags_list, type: Array
  field :options, type: Hash

  # Referenced associations
  belongs_to :author
  has_many :reviews

  # Embedded associations
  embeds_many :comments
  embeds_one :metadata

  # HABTM
  has_and_belongs_to_many :categories

  # Scopes
  scope :published, -> { where(published: true) }
  scope :popular, -> { where(:view_count.gt => 100) }
  scope :recent, -> { order(created_at: :desc) }
end
