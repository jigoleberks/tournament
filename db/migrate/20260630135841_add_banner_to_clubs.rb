class AddBannerToClubs < ActiveRecord::Migration[8.1]
  def change
    add_column :clubs, :banner_message, :string
    add_column :clubs, :banner_style, :integer, null: false, default: 0
  end
end
