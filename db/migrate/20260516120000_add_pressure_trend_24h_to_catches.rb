class AddPressureTrend24hToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :pressure_trend_24h_hpa, :decimal, precision: 5, scale: 2
  end
end
