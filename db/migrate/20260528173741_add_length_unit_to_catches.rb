class AddLengthUnitToCatches < ActiveRecord::Migration[8.1]
  def up
    add_column :catches, :length_unit, :string

    Catch.reset_column_information
    Catch.includes(:user).find_each do |c|
      c.update_column(
        :length_unit,
        Catches::InferLoggedUnit.call(
          length_inches: c.length_inches,
          user_length_unit: c.user&.length_unit
        )
      )
    end

    change_column_null :catches, :length_unit, false
  end

  def down
    remove_column :catches, :length_unit
  end
end
