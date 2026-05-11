class CreateClubRulesRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :club_rules_revisions do |t|
      t.references :club, null: false, foreign_key: true
      t.integer :season, null: false
      t.references :edited_by_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :club_rules_revisions, [ :club_id, :season, :created_at ],
              name: "idx_club_rules_revisions_lookup", order: { created_at: :desc }
  end
end
