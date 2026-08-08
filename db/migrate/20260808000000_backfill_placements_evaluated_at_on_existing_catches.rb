class BackfillPlacementsEvaluatedAtOnExistingCatches < ActiveRecord::Migration[8.1]
  # 20260718191633 added the stamp with no backfill, so every catch that
  # predates it reads as "pipeline never completed" — and a dedup retry
  # against one (a stuck queued row whose original upload succeeded, the
  # exact case the recover tool exists for) would re-run the full placement
  # pipeline: newer photo detectors re-flag a settled catch back to
  # needs_review and an ended tournament's leaderboard gets rebroadcast.
  # Pre-stamp catches are settled by definition — stamp them all.
  def up
    execute <<~SQL
      UPDATE catches
      SET placements_evaluated_at = COALESCE(synced_at, created_at)
      WHERE placements_evaluated_at IS NULL
    SQL
  end

  def down
    # Irreversible in spirit (the pre-stamp nils are not recoverable), but
    # nothing breaks with the stamps left in place.
  end
end
