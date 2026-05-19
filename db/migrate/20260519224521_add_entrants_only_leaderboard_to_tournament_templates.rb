class AddEntrantsOnlyLeaderboardToTournamentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_templates, :entrants_only_leaderboard, :boolean, default: false, null: false
  end
end
