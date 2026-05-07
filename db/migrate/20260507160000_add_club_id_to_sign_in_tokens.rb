class AddClubIdToSignInTokens < ActiveRecord::Migration[8.1]
  def change
    add_reference :sign_in_tokens, :club, foreign_key: true, null: true, index: true
  end
end
