class AddWindDirectionToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :wind_direction_deg, :decimal, precision: 5, scale: 1
  end
end
