class BroadcastBoatRenameJob < ApplicationJob
  queue_as :default

  # Fired by Boats::RenameEntries after a boat rename's cascade has already
  # committed. Placements::BroadcastLeaderboard renders synchronously, and
  # for a blind tournament (Catch the Average, Random Bag) that's a full-board
  # render plus one render per entry — doing that fan-out inline, once per
  # tournament the boat has ever fished, would make the boats-screen PATCH
  # itself slow for a boat with a season of history. The DB correction is
  # already durable by the time this runs; only the leaderboard redraw lands
  # a moment later. Soft posture: an entry deleted between enqueue and
  # perform is just skipped, not retried or raised.
  def perform(entry_ids:)
    entries = TournamentEntry.where(id: entry_ids).to_a
    return if entries.empty?

    tournaments = Tournament.where(id: entries.map(&:tournament_id).uniq).index_by(&:id)
    entries.group_by(&:tournament_id).each do |tournament_id, group|
      tournament = tournaments[tournament_id]
      next unless tournament

      Placements::BroadcastLeaderboard.call(tournament: tournament, changed_entry_ids: group.map(&:id))
    end
  end
end
