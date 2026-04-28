class AddTemplateSourceIdToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :template_source_id, :integer
  end
end
