class AddBlindLeaderboardToTournamentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_templates, :blind_leaderboard, :boolean, default: false, null: false
  end
end
