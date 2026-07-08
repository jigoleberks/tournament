class AddBingoLayoutToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :bingo_layout, :jsonb
  end
end

