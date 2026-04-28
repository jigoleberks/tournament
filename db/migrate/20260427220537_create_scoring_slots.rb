class CreateScoringSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :scoring_slots do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :species, null: false, foreign_key: true
      t.integer :slot_count, null: false
      t.timestamps
    end
    add_index :scoring_slots, [:tournament_id, :species_id], unique: true
  end
end
