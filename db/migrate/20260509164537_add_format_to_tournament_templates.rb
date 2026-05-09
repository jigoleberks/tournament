class AddFormatToTournamentTemplates < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_templates, :format, :integer, default: 0, null: false
  end
end
