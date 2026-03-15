# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name
      t.string :email
      t.integer :age
      t.boolean :active
      t.float :score
      t.decimal :balance
      t.text :bio
      t.date :born_on
      t.datetime :login_at
      t.string :password_digest
      t.integer :role

      t.timestamps
    end
  end
end
