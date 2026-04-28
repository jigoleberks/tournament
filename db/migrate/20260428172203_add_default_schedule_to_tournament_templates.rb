class AddDefaultScheduleToTournamentTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :tournament_templates, :default_weekday, :integer
    add_column :tournament_templates, :default_start_time, :time
    add_column :tournament_templates, :default_end_time, :time
  end
end
