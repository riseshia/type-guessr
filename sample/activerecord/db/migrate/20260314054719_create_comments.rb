class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.text :body
      t.references :commentable, polymorphic: true, null: false
      t.references :user, null: false, foreign_key: true
      t.string :entryable_type
      t.integer :entryable_id

      t.timestamps
    end
  end
end
