class AddLengthUnitToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :length_unit, :string, null: false, default: "inches"
  end
end
