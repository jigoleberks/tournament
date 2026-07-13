class AddRandomBagRangeToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :target_min_inches, :decimal, precision: 5, scale: 2, default: "70.0", null: false
    add_column :tournaments, :target_max_inches, :decimal, precision: 5, scale: 2, default: "100.0", null: false
  end
end
