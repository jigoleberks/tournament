class CreateSignInTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :sign_in_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end
    add_index :sign_in_tokens, :token, unique: true
  end
end
