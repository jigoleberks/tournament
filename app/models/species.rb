class Species < ApplicationRecord
  self.table_name = "species"

  # Display order for the catch-logging dropdown only (catches/new).
  # Species not listed here fall to the end, ordered alphabetically.
  LOG_ORDER = ["Walleye", "Perch", "Pike", "Stocked Trout", "Lake Trout", "Bass", "Other"].freeze

  has_many :scoring_slots, dependent: :restrict_with_error
  has_many :catch_placements, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def self.in_log_order
    all.sort_by { |species| [LOG_ORDER.index(species.name) || LOG_ORDER.size, species.name] }
  end
end
