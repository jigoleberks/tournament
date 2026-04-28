class AddRequiresReleaseVideoToTournaments < ActiveRecord::Migration[8.0]
  def change
    add_column :tournaments, :requires_release_video, :boolean, null: false, default: true
  end
end
