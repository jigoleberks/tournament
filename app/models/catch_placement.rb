class CatchPlacement < ApplicationRecord
  belongs_to :catch
  belongs_to :tournament
  belongs_to :tournament_entry
  belongs_to :species

  # Only active placements compete for a slot. Deactivated rows are kept as an
  # audit trail (e.g. after a judge changes a catch's species), so they must NOT
  # reserve their (catch, entry, species, slot) — otherwise re-placing a catch
  # under a species it previously held collides with its own tombstone row.
  # Mirrors the partial DB index idx_active_placements_uniq_per_slot (WHERE active).
  validates :slot_index, presence: true,
            uniqueness: { scope: [:catch_id, :tournament_entry_id, :species_id],
                          conditions: -> { where(active: true) },
                          if: :active? }

  scope :active, -> { where(active: true) }
end
