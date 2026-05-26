class AddWeightTextToCatches < ActiveRecord::Migration[8.1]
  def change
    add_column :catches, :weight_text, :string, limit: 32
  end
end
