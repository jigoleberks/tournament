class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.references :club, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :users, [:club_id, :email], unique: true
  end
end
