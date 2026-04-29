class AddKindAndAttemptsToSignInTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :sign_in_tokens, :kind, :string, default: "link", null: false
    add_column :sign_in_tokens, :attempts, :integer, default: 0, null: false
    add_index :sign_in_tokens, [:user_id, :kind]
  end
end
