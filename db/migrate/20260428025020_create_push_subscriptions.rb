class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.datetime :muted_until
      t.integer :muted_tournament_ids, array: true, default: []
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
