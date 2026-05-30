class AddLogbookFieldsToCatches < ActiveRecord::Migration[8.1]
  def change
    add_column :catches, :water_depth_feet, :decimal, precision: 5, scale: 2
    add_column :catches, :water_temperature_c, :decimal, precision: 5, scale: 2
    add_column :catches, :structure, :integer
    add_reference :catches, :bait, null: true, foreign_key: true
  end
end
