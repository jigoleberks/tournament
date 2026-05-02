class AddLocalToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :local, :boolean, default: true, null: false
  end
end
