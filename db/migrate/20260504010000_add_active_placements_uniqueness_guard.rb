class AddActivePlacementsUniquenessGuard < ActiveRecord::Migration[8.0]
  def up
    # Defensive cleanup before the unique index. If a concurrent-writer bug ever
    # produced duplicate active placements for the same (entry, species, slot_index),
    # the migration would otherwise fail to apply. Keep the most recent and deactivate
    # the rest, matching the "biggest fish wins the slot" intent as best we can without
    # re-running the placement logic.
    execute <<~SQL
      UPDATE catch_placements
      SET active = false
      WHERE id IN (
        SELECT id FROM (
          SELECT id,
                 row_number() OVER (
                   PARTITION BY tournament_entry_id, species_id, slot_index
                   ORDER BY created_at DESC, id DESC
                 ) AS rn
          FROM catch_placements
          WHERE active = true
        ) AS dup
        WHERE rn > 1
      )
    SQL

    add_index :catch_placements,
              [ :tournament_entry_id, :species_id, :slot_index ],
              unique: true,
              where: "active = true",
              name: "idx_active_placements_uniq_per_slot"
  end

  def down
    remove_index :catch_placements, name: "idx_active_placements_uniq_per_slot"
  end
end
