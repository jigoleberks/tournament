class User < ApplicationRecord
  has_many :club_memberships, dependent: :destroy
  has_many :clubs_via_memberships, through: :club_memberships, source: :club
  has_many :tournament_entry_members, dependent: :destroy
  has_many :tournament_entries, through: :tournament_entry_members
  has_many :tournament_judges, dependent: :destroy
  has_many :catches, dependent: :restrict_with_error
  has_many :push_subscriptions, dependent: :destroy
  has_many :judge_actions, foreign_key: :judge_user_id, dependent: :destroy

  validates :name, :email, presence: true
  validates :email, uniqueness: { case_sensitive: false }

  scope :active, -> { where(deactivated_at: nil) }

  def deactivated?
    deactivated_at.present?
  end

  LENGTH_UNITS = %w[inches centimeters].freeze
  validates :length_unit, inclusion: { in: LENGTH_UNITS }

  def metric?
    length_unit == "centimeters"
  end

  def organizer_in?(club)
    return false unless club
    club_memberships.active.where(club: club, role: :organizer).exists?
  end

  def member_of?(club)
    return false unless club
    club_memberships.active.where(club: club).exists?
  end
end
