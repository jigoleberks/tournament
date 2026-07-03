class Species < ApplicationRecord
  self.table_name = "species"

  # Canonical name for the Tagged Walleye species row. Centralized here so
  # Tournament/Catch validations and view lookups don't all hard-code the
  # string in different places.
  TAGGED_WALLEYE_NAME = "Tagged Walleye".freeze

  # Canonical name for the ordinary Walleye species row (distinct from the
  # "Tagged Walleye" species). Used by the Pro Walleye format's slot validation.
  WALLEYE_NAME = "Walleye".freeze

  # Display order for the catch-logging dropdown only (catches/new).
  # Species not listed here fall to the end, ordered alphabetically.
  LOG_ORDER = ["Walleye", "Perch", "Pike", "Stocked Trout", "Lake Trout", "Bass", TAGGED_WALLEYE_NAME, "Other"].freeze

  has_many :scoring_slots, dependent: :restrict_with_error
  has_many :catch_placements, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def self.in_log_order
    all.sort_by do |species|
      rank = LOG_ORDER.index { |name| name.casecmp?(species.name) } || LOG_ORDER.size
      [rank, species.name.downcase]
    end
  end

  def self.tagged_walleye
    find_by("lower(name) = ?", TAGGED_WALLEYE_NAME.downcase)
  end

  def self.walleye
    find_by("lower(name) = ?", WALLEYE_NAME.downcase)
  end

  def tagged_walleye?
    name.to_s.casecmp?(TAGGED_WALLEYE_NAME)
  end

  def walleye?
    name.to_s.casecmp?(WALLEYE_NAME)
  end
end
