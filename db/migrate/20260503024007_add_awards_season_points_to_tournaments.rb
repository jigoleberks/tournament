class AddAwardsSeasonPointsToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :awards_season_points, :boolean, default: false, null: false
  end
end
