class Club < ApplicationRecord
  has_many :club_memberships, dependent: :destroy
  has_many :members, through: :club_memberships, source: :user
  has_many :tournaments, dependent: :destroy
  has_many :tournament_templates, dependent: :destroy
  has_many :rules_revisions, class_name: "ClubRulesRevision", dependent: :destroy
  enum :active_rules_season, { open_water: 0, ice: 1 }, prefix: true
  validates :name, presence: true, uniqueness: true

  def current_rules_revision
    ClubRulesRevision.latest_for(club: self, season: active_rules_season)
  end
end
