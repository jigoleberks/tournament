class RemoveKindFromTournaments < ActiveRecord::Migration[8.1]
  def change
    remove_column :tournaments, :kind, :integer, default: 0, null: false
  end
end
