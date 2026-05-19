class AddEntrantsOnlyLeaderboardToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :entrants_only_leaderboard, :boolean, default: false, null: false
  end
end
