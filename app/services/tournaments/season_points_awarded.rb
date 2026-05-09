module Tournaments
  class SeasonPointsAwarded
    ATTENDANCE_BONUS = 0.5

    def self.call(tournament:)
      return {} unless tournament.awards_season_points?
      return {} unless tournament.ended?

      angler_count = ::Tournaments::AnglerCount.call(tournament: tournament)
      scale = ::Tournaments::PointsScale.call(angler_count: angler_count)
      return {} if scale.nil?

      placers = ::Tournaments::TopThree.call(tournament: tournament)

      awards = {}
      placers.each_with_index do |row, idx|
        points = scale[idx]
        next unless points
        row[:entry].users.each { |u| awards[u.id] = (awards[u.id] || 0) + points }
      end

      member_ids = ::TournamentEntryMember
        .joins(:tournament_entry)
        .where(tournament_entries: { tournament_id: tournament.id })
        .distinct
        .pluck(:user_id)
      member_ids.each { |uid| awards[uid] = (awards[uid] || 0) + ATTENDANCE_BONUS }

      awards
    end
  end
end
