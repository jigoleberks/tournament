class TournamentTemplateScoringSlot < ApplicationRecord
  belongs_to :tournament_template
  belongs_to :species
  validates :slot_count, numericality: { greater_than: 0 }
end
