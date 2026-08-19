class AddBoatToTournamentEntries < ActiveRecord::Migration[8.0]
  def change
    add_reference :tournament_entries, :boat, foreign_key: true, null: true
  end
end
