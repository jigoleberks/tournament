class User < ApplicationRecord
  belongs_to :club
  has_many :tournament_entry_members, dependent: :destroy
  has_many :tournament_entries, through: :tournament_entry_members
  has_many :tournament_judges, dependent: :destroy
  has_many :catches, dependent: :restrict_with_error
  has_many :push_subscriptions, dependent: :destroy
  has_many :judge_actions, foreign_key: :judge_user_id, dependent: :destroy
  enum :role, { member: 0, organizer: 1 }
  validates :name, :email, presence: true
  validates :email, uniqueness: { scope: :club_id }

  LENGTH_UNITS = %w[inches centimeters].freeze
  validates :length_unit, inclusion: { in: LENGTH_UNITS }

  def metric?
    length_unit == "centimeters"
  end
end
