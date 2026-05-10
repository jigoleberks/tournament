class AddActiveRulesSeasonToClubs < ActiveRecord::Migration[8.1]
  def change
    add_column :clubs, :active_rules_season, :integer, null: false, default: 0
  end
end
