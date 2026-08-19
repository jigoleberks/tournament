class AddLinkGroupIdToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :link_group_id, :string
    add_index :tournaments, :link_group_id
  end
end
