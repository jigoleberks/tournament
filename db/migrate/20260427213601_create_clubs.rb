class CreateClubs < ActiveRecord::Migration[8.0]
  def change
    create_table :clubs do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :clubs, :name, unique: true
  end
end
