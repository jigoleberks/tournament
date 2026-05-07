class Club < ApplicationRecord
  has_many :club_memberships, dependent: :destroy
  has_many :members, through: :club_memberships, source: :user
  has_many :tournaments, dependent: :destroy
  has_many :tournament_templates, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
