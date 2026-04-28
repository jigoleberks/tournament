class Species < ApplicationRecord
  self.table_name = "species"
  belongs_to :club
  has_many :scoring_slots, dependent: :restrict_with_error
  has_many :catch_placements, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { scope: :club_id }
end
