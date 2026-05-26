class DropLegacyPlacementsUniqIndex < ActiveRecord::Migration[8.0]
  # idx_placements_uniq is a non-partial unique index on
  # (catch_id, tournament_entry_id, species_id, slot_index). It predates the
  # partial idx_active_placements_uniq_per_slot (added in
  # 20260504010000_add_active_placements_uniqueness_guard), which is the correct
  # "one fish per active slot" guard.
  #
  # Because idx_placements_uniq also covers DEACTIVATED rows, a catch's own
  # tombstone placement permanently reserves its (entry, species, slot) key.
  # That blocks re-placing the catch under a species it previously held — so a
  # judge/organizer can change a catch's species once but not change it back.
  #
  # The partial index is stricter for active rows (it omits catch_id, forbidding
  # ANY two active rows at the same entry/species/slot) and fully supersedes the
  # non-partial one. Drop the legacy index so deactivated audit rows can
  # accumulate and species can be re-classified any number of times.
  def up
    remove_index :catch_placements, name: "idx_placements_uniq"
  end

  def down
    add_index :catch_placements,
              [:catch_id, :tournament_entry_id, :species_id, :slot_index],
              unique: true,
              name: "idx_placements_uniq"
  end
end
