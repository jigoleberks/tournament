class CatchPlacement < ApplicationRecord
  belongs_to :catch
  belongs_to :tournament
  belongs_to :tournament_entry
  belongs_to :species

  validates :slot_index, presence: true,
            uniqueness: { scope: [:catch_id, :tournament_entry_id, :species_id] }

  scope :active, -> { where(active: true) }
end
