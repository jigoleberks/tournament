class AddJudgedToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :judged, :boolean, null: false, default: false
  end
end
