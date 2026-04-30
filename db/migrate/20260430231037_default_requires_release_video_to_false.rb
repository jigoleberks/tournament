class DefaultRequiresReleaseVideoToFalse < ActiveRecord::Migration[8.0]
  def change
    change_column_default :tournaments, :requires_release_video, from: true, to: false
  end
end
