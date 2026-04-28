class CreateTournamentEntryMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :tournament_entry_members do |t|
      t.references :tournament_entry, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    # An angler can only be in one entry per tournament; expressed via a
    # unique index over (tournament_id, user_id) using a generated column
    # would require a more complex migration. We enforce in Ruby instead
    # and add a covering index to keep the lookup fast.
    add_index :tournament_entry_members, [:tournament_entry_id, :user_id], unique: true
  end
end
