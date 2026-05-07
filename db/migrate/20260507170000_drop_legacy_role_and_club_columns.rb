class DropLegacyRoleAndClubColumns < ActiveRecord::Migration[8.1]
  def change
    remove_index :users, name: "index_users_on_club_id_and_email"
    remove_index :users, :club_id

    remove_foreign_key :users, :clubs
    remove_column :users, :club_id, :bigint, null: false
    remove_column :users, :role, :integer, null: false, default: 0

    add_index :users, :email, unique: true

    remove_index :species, name: "index_species_on_club_id_and_name"
    remove_index :species, :club_id
    remove_foreign_key :species, :clubs
    remove_column :species, :club_id, :bigint, null: false

    add_index :species, :name, unique: true
  end
end
