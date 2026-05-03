module SeasonPoints
  class CurrentSeasonTag
    def self.call(club:)
      club.tournaments
        .where(awards_season_points: true)
        .where.not(season_tag: nil)
        .order(starts_at: :desc)
        .limit(1)
        .pluck(:season_tag)
        .first
    end
  end
end
