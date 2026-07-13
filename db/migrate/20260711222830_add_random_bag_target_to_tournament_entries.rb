class AddRandomBagTargetToTournamentEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :tournament_entries, :random_bag_target_inches, :decimal, precision: 5, scale: 2
  end
end
