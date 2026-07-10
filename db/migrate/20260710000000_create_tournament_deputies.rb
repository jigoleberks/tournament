class CreateTournamentDeputies < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_deputies do |t|
      t.references :tournament,      null: false, foreign_key: true
      t.references :user,            null: false, foreign_key: true
      t.references :granted_by_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :tournament_deputies, [:tournament_id, :user_id], unique: true
  end
end
