# frozen_string_literal: true

class CreateTags < ActiveRecord::Migration[8.1]
  def change
    create_table :tags do |t|
      t.string :name

      t.timestamps
    end
  end
end
