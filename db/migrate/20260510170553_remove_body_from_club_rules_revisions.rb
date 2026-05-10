class RemoveBodyFromClubRulesRevisions < ActiveRecord::Migration[8.1]
  def change
    remove_column :club_rules_revisions, :body, :text
  end
end
