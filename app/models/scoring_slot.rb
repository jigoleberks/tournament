class ScoringSlot < ApplicationRecord
  belongs_to :tournament
  belongs_to :species
  validates :slot_count, numericality: { greater_than: 0 }
  validates :species_id, uniqueness: { scope: :tournament_id }
end
