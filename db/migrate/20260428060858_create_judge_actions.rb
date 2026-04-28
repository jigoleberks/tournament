class CreateJudgeActions < ActiveRecord::Migration[8.0]
  def change
    create_table :judge_actions do |t|
      t.references :judge_user, null: false, foreign_key: { to_table: :users }
      t.references :catch, null: false, foreign_key: true
      t.integer :action, null: false
      t.text :note
      t.jsonb :before_state, default: {}
      t.jsonb :after_state,  default: {}
      t.timestamps
    end
    add_index :judge_actions, [:catch_id, :created_at]
  end
end
