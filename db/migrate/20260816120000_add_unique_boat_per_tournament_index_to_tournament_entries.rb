class AddUniqueBoatPerTournamentIndexToTournamentEntries < ActiveRecord::Migration[8.0]
  def change
    # A boat can only ever have one live entry per tournament. SyncEntry
    # already guards this in application code, but a mirrored counterpart
    # that wrongly loses its boat_id (see the fix that shipped alongside this
    # index) lets the boat reappear in the picker and a second tap create a
    # duplicate entry for it — this index makes that impossible at the DB
    # layer too, not just by convention.
    add_index :tournament_entries, [:tournament_id, :boat_id], unique: true,
              where: "boat_id IS NOT NULL", name: "index_tournament_entries_on_tournament_and_boat_uniq"
  end
end
