# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.string :subject
      t.text :body

      t.timestamps
    end
  end
end
