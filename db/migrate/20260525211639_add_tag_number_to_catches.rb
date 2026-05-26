class AddTagNumberToCatches < ActiveRecord::Migration[8.1]
  def change
    add_column :catches, :tag_number, :string, limit: 16
  end
end
