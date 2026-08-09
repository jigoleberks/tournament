# "A placement run has completed for this catch", stamped INSIDE
# Catches::PlaceInSlots' own transaction. Distinct from placements_evaluated_at,
# which is written last (after the broadcast) so a crashed pipeline can be
# retried — and is therefore still NULL while a concurrent duplicate POST is
# racing the original run. Bingo keeps no CatchPlacement rows, so this is the
# only thing that can tell that second run it has nothing to do.
#
# Backfilled for existing rows: every catch that already holds a placement has
# plainly been through a completed run. Bingo catches keep no placements and so
# stay NULL, which is harmless — the guard only suppresses a *repeat* of the
# first-placement path, and those runs are long finished.
class AddPlacedAtToCatches < ActiveRecord::Migration[8.1]
  def up
    add_column :catches, :placed_at, :datetime
    execute <<~SQL
      UPDATE catches SET placed_at = catches.created_at
      WHERE EXISTS (SELECT 1 FROM catch_placements WHERE catch_placements.catch_id = catches.id)
    SQL
  end

  def down
    remove_column :catches, :placed_at
  end
end
