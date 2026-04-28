class Club < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :species, dependent: :destroy
  has_many :tournaments, dependent: :destroy
  has_many :tournament_templates, dependent: :destroy
  validates :name, presence: true, uniqueness: true
end
