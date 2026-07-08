module Tournaments
  class WinnersFor
    def self.call(tournaments:)
      return {} if tournaments.empty?

      tournament_ids = tournaments.map(&:id)

      entries_by_tid = TournamentEntry
        .where(tournament_id: tournament_ids)
        .includes(:users)
        .group_by(&:tournament_id)

      placements_by_tid = CatchPlacement.active
        .where(tournament_id: tournament_ids)
        .includes(catch: [:species, :user, :logged_by_user, { judge_actions: :judge_user }])
        .group_by(&:tournament_id)

      capacity_by_tid = ScoringSlot
        .where(tournament_id: tournament_ids)
        .group(:tournament_id)
        .sum(:slot_count)

      tournaments.each_with_object({}) do |t, h|
        rows = ::Leaderboards::Build.call(
          tournament: t,
          entries: entries_by_tid[t.id] || [],
          placements: placements_by_tid[t.id] || [],
          total_capacity: capacity_by_tid[t.id] || 0
        )
        h[t.id] = ::Leaderboards::QualifiedRows.call(tournament: t, rows: rows).first&.dig(:entry)
      end
    end
  end
end
