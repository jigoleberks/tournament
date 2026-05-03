module SeasonPoints
  class Tournaments
    def self.call(club:, season_tag:)
      return ::Tournament.none if season_tag.nil?

      club.tournaments
        .where(awards_season_points: true, season_tag: season_tag)
        .where("ends_at < ?", ::Time.current)
        .order(ends_at: :desc)
    end
  end
end
