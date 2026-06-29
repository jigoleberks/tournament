class CreateUserEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :user_events do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false
      t.string :user_agent
      t.string :app_build
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :user_events, [:user_id, :created_at]
  end
end
