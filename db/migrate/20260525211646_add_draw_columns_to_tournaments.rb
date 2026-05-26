class AddDrawColumnsToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_reference :tournaments, :drawn_winning_placement,
                  foreign_key: { to_table: :catch_placements }, null: true, index: true
    add_column    :tournaments, :drawn_at, :datetime
    add_reference :tournaments, :drawn_by_user,
                  foreign_key: { to_table: :users }, null: true, index: true
  end
end
