module Tournaments
  class SeasonPointsAwarded
    ATTENDANCE_BONUS = 0.5

    # `top_three` and `member_ids` can be injected by batch callers (e.g.
    # SeasonPoints::Standings) that already preloaded them, so this service
    # doesn't re-query per tournament. Left nil, each is computed on demand.
    # The angler count (which sets the points scale) is the distinct member
    # count, so it derives from `member_ids` — no separate AnglerCount query.
    def self.call(tournament:, top_three: nil, member_ids: nil)
      return {} unless tournament.awards_season_points?
      return {} unless tournament.ended?

      member_ids ||= member_ids_for(tournament)
      scale = ::Tournaments::PointsScale.call(angler_count: member_ids.size)
      return {} if scale.nil?

      placers = top_three || ::Tournaments::TopThree.call(tournament: tournament)

      awards = {}
      placers.each_with_index do |row, idx|
        points = scale[idx]
        next unless points
        row[:entry].users.each { |u| awards[u.id] = (awards[u.id] || 0) + points }
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
