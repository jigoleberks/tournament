class AddFlagsToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :flags, :text, array: true, default: [], null: false
  end
end
