class CreateBaits < ActiveRecord::Migration[8.1]
  def change
    create_table :baits do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :color
      t.string :weight
      t.string :lure_type
      t.string :bait_type
      t.datetime :archived_at
      t.timestamps
    end
    add_index :baits, [:user_id, :archived_at]
  end
end
