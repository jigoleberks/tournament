class AddIssuedByUserIdToSignInTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :sign_in_tokens, :issued_by_user, foreign_key: { to_table: :users }, null: true, index: true
  end
end
