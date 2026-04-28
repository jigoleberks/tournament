class CreateTournamentTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_templates do |t|
      t.references :club, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :mode, null: false, default: 0
      t.integer :default_duration_days
      t.timestamps
    end
  end
end
