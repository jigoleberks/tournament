module Tournaments
  class SeasonPointsAwarded
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
      awards
    end
  end
end
