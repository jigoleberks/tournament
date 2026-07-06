module SeasonPoints
  class Standings
    def self.call(club:, season_tag:)
      return [] if season_tag.nil?

      tournaments = club.tournaments
        .where(awards_season_points: true, season_tag: season_tag)
        .where("ends_at < ?", ::Time.current)
        .to_a
      return [] if tournaments.empty?

      tournament_ids = tournaments.map(&:id)

      # Batch-preload everything SeasonPointsAwarded/Leaderboards::Build need,
      # grouped by tournament_id, so the per-tournament loop issues no queries
      # (mirrors Tournaments::WinnersFor). Without this, each tournament ran a
      # full leaderboard build plus an angler-count and member pluck of its own.
      entries_by_tid = ::TournamentEntry
        .where(tournament_id: tournament_ids)
        .includes(:users)
        .group_by(&:tournament_id)

      placements_by_tid = ::CatchPlacement.active
        .where(tournament_id: tournament_ids)
        .includes(catch: [:species, :user, :logged_by_user, { judge_actions: :judge_user }])
        .group_by(&:tournament_id)

      capacity_by_tid = ::ScoringSlot
        .where(tournament_id: tournament_ids)
        .group(:tournament_id)
        .sum(:slot_count)

      member_ids_by_tid = ::TournamentEntryMember
        .joins(:tournament_entry)
        .where(tournament_entries: { tournament_id: tournament_ids })
        .distinct
        .pluck("tournament_entries.tournament_id", :user_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(tid, uid), h| h[tid] << uid }

      totals = Hash.new(0)
      breakdowns = Hash.new { |h, k| h[k] = [] }

      tournaments.each do |t|
        rows = ::Leaderboards::Build.call(
          tournament: t,
          entries: entries_by_tid[t.id] || [],
          placements: placements_by_tid[t.id] || [],
          total_capacity: capacity_by_tid[t.id] || 0
        )
        top_three = ::Leaderboards::QualifiedRows.call(tournament: t, rows: rows).first(3)
        awards = ::Tournaments::SeasonPointsAwarded.call(
          tournament: t,
          top_three: top_three,
          member_ids: member_ids_by_tid[t.id] || []
        )
        awards.each do |user_id, points|
          totals[user_id] += points
          breakdowns[user_id] << { tournament_id: t.id, tournament_name: t.name, points: points }
        end
      end

      users_by_id = ::User.where(id: totals.keys).index_by(&:id)
      rows = totals.map do |user_id, points|
        {
          user: users_by_id[user_id],
          points: points,
          breakdown: breakdowns[user_id]
        }
      end
      rows.sort_by { |r| [-r[:points], r[:user].name.downcase] }
    end
  end
end
