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

    # Collapse legacy per-club species duplicates (each club had its own "Walleye") onto the lowest-id row before enforcing UNIQUE(name).
    reversible do |dir|
      dir.up do
        %w[catches catch_placements scoring_slots tournament_template_scoring_slots].each do |table|
          execute <<~SQL
            UPDATE #{table} t
            SET species_id = m.keeper_id
            FROM (
              SELECT s.id AS old_id, k.keeper_id
              FROM species s
              JOIN (
                SELECT MIN(id) AS keeper_id, LOWER(name) AS lname
                FROM species
                GROUP BY LOWER(name)
              ) k ON LOWER(s.name) = k.lname
              WHERE s.id <> k.keeper_id
            ) m
            WHERE t.species_id = m.old_id;
          SQL
        end

        execute <<~SQL
          DELETE FROM species s
          USING (
            SELECT MIN(id) AS keeper_id, LOWER(name) AS lname
            FROM species
            GROUP BY LOWER(name)
          ) k
          WHERE LOWER(s.name) = k.lname AND s.id <> k.keeper_id;
        SQL
      end
    end

    add_index :species, :name, unique: true
  end
end
