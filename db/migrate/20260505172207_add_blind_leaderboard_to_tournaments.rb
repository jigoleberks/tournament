class AddBlindLeaderboardToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :blind_leaderboard, :boolean, default: false, null: false
  end
end
