# frozen_string_literal: true

class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title
      t.text :body
      t.boolean :published
      t.datetime :published_at
      t.references :user, null: false, foreign_key: true
      t.integer :status

      t.timestamps
    end
  end
end
