# frozen_string_literal: true

class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.json :settings

      t.timestamps
    end
  end
end
