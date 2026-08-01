module Tournaments
  class SeasonPointsAwarded
    ATTENDANCE_BONUS = 0.5
    MIN_ENTRIES_FOR_PLACEMENT_POINTS = 3

    # `top_three`, `member_ids`, and `entry_count` can be injected by batch
    # callers (e.g. SeasonPoints::Standings) that already preloaded them, so
    # this service doesn't re-query per tournament. Left nil, each is computed
    # on demand. The angler count (which sets the points scale) is the distinct
    # member count, so it derives from `member_ids`. The placement-points
    # cutoff counts entries — 3 solo anglers or 3 teams — while the scale
    # tiers stay angler-based.
    def self.call(tournament:, top_three: nil, member_ids: nil, entry_count: nil)
      return {} unless tournament.awards_season_points?
      return {} unless tournament.ended?

      member_ids ||= member_ids_for(tournament)
      entry_count ||= tournament.tournament_entries.count
      scale = ::Tournaments::PointsScale.call(angler_count: member_ids.size)

      awards = {}
      if entry_count >= MIN_ENTRIES_FOR_PLACEMENT_POINTS && scale
        placers = top_three || ::Tournaments::TopThree.call(tournament: tournament)
        placers.each_with_index do |row, idx|
          points = scale[idx]
          next unless points
          row[:entry].users.each { |u| awards[u.id] = (awards[u.id] || 0) + points }
        end
      end

      member_ids.each { |uid| awards[uid] = (awards[uid] || 0) + ATTENDANCE_BONUS }

      awards
    end

    def self.member_ids_for(tournament)
      ::TournamentEntryMember
        .joins(:tournament_entry)
        .where(tournament_entries: { tournament_id: tournament.id })
        .distinct
        .pluck(:user_id)
    end
    private_class_method :member_ids_for
  end
end
