class AllowNullBodyOnClubRulesRevisions < ActiveRecord::Migration[8.1]
  def change
    change_column_null :club_rules_revisions, :body, true
  end
end
