class CreateTournamentTemplateScoringSlots < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_template_scoring_slots do |t|
      t.references :tournament_template, null: false, foreign_key: true
      t.references :species, null: false, foreign_key: true
      t.integer :slot_count, null: false, default: 1
      t.timestamps
    end
  end
end
