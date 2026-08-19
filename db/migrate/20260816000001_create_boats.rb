class CreateBoats < ActiveRecord::Migration[8.0]
  def change
    create_table :boats do |t|
      t.references :club, null: false, foreign_key: true
      t.string :name, null: false
      t.bigint :captain_user_id, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :boats, :captain_user_id
    add_index :boats, "club_id, lower(name)", unique: true, name: "index_boats_on_club_id_and_lower_name"
  end
end
