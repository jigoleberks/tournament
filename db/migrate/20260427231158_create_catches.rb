class CreateCatches < ActiveRecord::Migration[8.0]
  def change
    create_table :catches do |t|
      t.references :user, null: false, foreign_key: true
      t.references :species, null: false, foreign_key: true
      t.decimal :length_inches, precision: 5, scale: 2, null: false
      t.datetime :captured_at_device, null: false
      t.datetime :captured_at_gps
      t.decimal :latitude, precision: 9, scale: 6
      t.decimal :longitude, precision: 9, scale: 6
      t.decimal :gps_accuracy_m, precision: 7, scale: 1
      t.string :app_build
      t.integer :status, null: false, default: 1   # synced
      t.string :client_uuid, null: false
      t.datetime :synced_at
      t.timestamps
    end
    add_index :catches, :client_uuid, unique: true
  end
end
