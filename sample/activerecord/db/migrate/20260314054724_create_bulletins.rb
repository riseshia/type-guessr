class CreateBulletins < ActiveRecord::Migration[8.1]
  def change
    create_table :bulletins do |t|
      t.string :title
      t.text :body
      t.boolean :pinned

      t.timestamps
    end
  end
end
