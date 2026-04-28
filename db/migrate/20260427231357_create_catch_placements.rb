class CreateCatchPlacements < ActiveRecord::Migration[8.0]
  def change
    create_table :catch_placements do |t|
      t.references :catch, null: false, foreign_key: true
      t.references :tournament, null: false, foreign_key: true
      t.references :tournament_entry, null: false, foreign_key: true
      t.references :species, null: false, foreign_key: true
      t.integer :slot_index, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :catch_placements,
              [:catch_id, :tournament_entry_id, :species_id, :slot_index],
              unique: true,
              name: "idx_placements_uniq"
    add_index :catch_placements,
              [:tournament_id, :species_id, :slot_index, :active],
              name: "idx_placements_leaderboard"
  end
end
