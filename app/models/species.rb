class Species < ApplicationRecord
  self.table_name = "species"

  # Display order for the catch-logging dropdown only (catches/new).
  # Species not listed here fall to the end, ordered alphabetically.
  LOG_ORDER = ["Walleye", "Perch", "Pike", "Stocked Trout", "Lake Trout", "Bass", "Tagged Walleye", "Other"].freeze

  has_many :scoring_slots, dependent: :restrict_with_error
  has_many :catch_placements, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def self.in_log_order
    all.sort_by do |species|
      rank = LOG_ORDER.index { |name| name.casecmp?(species.name) } || LOG_ORDER.size
      [rank, species.name.downcase]
    end
  end
end
