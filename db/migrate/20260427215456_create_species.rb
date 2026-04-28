class CreateSpecies < ActiveRecord::Migration[8.0]
  def change
    create_table :species do |t|
      t.references :club, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :species, [:club_id, :name], unique: true
  end
end
