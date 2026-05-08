class CreateClubMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :club_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :club, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.datetime :deactivated_at
      t.timestamps
    end

    add_index :club_memberships, [ :user_id, :club_id ], unique: true
    add_index :club_memberships, :deactivated_at
    add_column :users, :admin, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO club_memberships (user_id, club_id, role, deactivated_at, created_at, updated_at)
          SELECT id, club_id, role, deactivated_at, NOW(), NOW()
          FROM users
        SQL
      end
    end
  end
end
