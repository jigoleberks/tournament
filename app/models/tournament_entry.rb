class TournamentEntry < ApplicationRecord
  belongs_to :tournament
  has_many :tournament_entry_members, dependent: :destroy
  has_many :users, through: :tournament_entry_members
  has_many :catch_placements, dependent: :destroy

  def display_name
    name.presence || users.pluck(:name).join(" + ")
  end
end
