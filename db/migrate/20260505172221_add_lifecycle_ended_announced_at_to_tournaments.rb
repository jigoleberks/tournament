class AddLifecycleEndedAnnouncedAtToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_column :tournaments, :lifecycle_ended_announced_at, :datetime
  end
end
