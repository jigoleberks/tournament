class CreateTournaments < ActiveRecord::Migration[8.0]
  def change
    create_table :tournaments do |t|
      t.references :club, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :kind, null: false, default: 0
      t.integer :mode, null: false, default: 0
      t.datetime :starts_at, null: false
      t.datetime :ends_at
      t.string :season_tag
      t.timestamps
    end
    add_index :tournaments, [:club_id, :starts_at, :ends_at]
  end
end
