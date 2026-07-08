class AddSeasonTagToTournamentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_templates, :season_tag, :string
  end
end
