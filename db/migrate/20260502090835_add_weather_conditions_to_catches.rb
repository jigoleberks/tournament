class AddWeatherConditionsToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :temperature_c, :decimal, precision: 5, scale: 2
    add_column :catches, :wind_speed_kph, :decimal, precision: 5, scale: 1
    add_column :catches, :barometric_pressure_hpa, :decimal, precision: 7, scale: 2
    add_column :catches, :moon_phase, :string
    add_column :catches, :moon_phase_fraction, :decimal, precision: 5, scale: 4
  end
end
