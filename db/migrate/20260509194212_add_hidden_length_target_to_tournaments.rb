class AddHiddenLengthTargetToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :hidden_length_target, :decimal, precision: 5, scale: 2
  end
end
