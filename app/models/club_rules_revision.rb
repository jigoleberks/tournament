class ClubRulesRevision < ApplicationRecord
  belongs_to :club
  belongs_to :edited_by_user, class_name: "User"

  has_rich_text :body

  enum :season, { open_water: 0, ice: 1 }, prefix: true

  validates :body, presence: true

  def self.latest_for(club:, season:)
    where(club: club, season: season).order(created_at: :desc).first
  end
end
