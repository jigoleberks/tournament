class AddPlasticToBaits < ActiveRecord::Migration[8.1]
  def change
    add_column :baits, :plastic, :string
    add_column :baits, :plastic_color, :string
  end
end
