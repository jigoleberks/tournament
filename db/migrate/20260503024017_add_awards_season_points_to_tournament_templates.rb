class AddAwardsSeasonPointsToTournamentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_templates, :awards_season_points, :boolean, default: false, null: false
  end
end
