class AddShowBannerToClubMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :club_memberships, :show_banner, :boolean, null: false, default: false
  end
end
