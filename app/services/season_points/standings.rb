module SeasonPoints
  class Standings
    def self.call(club:, season_tag:)
      return [] if season_tag.nil?

      tournaments = club.tournaments
        .where(awards_season_points: true, season_tag: season_tag)
        .where("ends_at < ?", ::Time.current)

      totals = Hash.new(0)
      breakdowns = Hash.new { |h, k| h[k] = [] }

      tournaments.each do |t|
        awards = ::Tournaments::SeasonPointsAwarded.call(tournament: t)
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
