class CreateTournamentJudges < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_judges do |t|
      t.references :tournament, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :tournament_judges, [:tournament_id, :user_id], unique: true
  end
end
