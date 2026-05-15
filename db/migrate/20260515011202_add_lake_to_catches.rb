class AddLakeToCatches < ActiveRecord::Migration[8.0]
  def change
    add_column :catches, :lake, :string, limit: 64
    add_index  :catches, :lake
  end
end
