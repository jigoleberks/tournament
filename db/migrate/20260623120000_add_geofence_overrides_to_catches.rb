class AddGeofenceOverridesToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :override_in_lake, :boolean, default: false, null: false
    add_column :catches, :override_in_sask, :boolean, default: false, null: false
  end
end
