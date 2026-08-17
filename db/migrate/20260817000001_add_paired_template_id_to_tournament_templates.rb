class AddPairedTemplateIdToTournamentTemplates < ActiveRecord::Migration[8.0]
  def change
    add_column :tournament_templates, :paired_template_id, :bigint
    add_index :tournament_templates, :paired_template_id
  end
end
