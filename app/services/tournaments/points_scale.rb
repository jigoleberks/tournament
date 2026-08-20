module Tournaments
  # The one dispatch point for season point amounts. Given a club's configured
  # scheme and how many entries (boats/teams) competed, returns the per-place
  # amounts — [9, 6, 3], [8, 7, 6, 5, 4, 3, 2, 1], whatever the club set — or
  # nil when the field was too small to pay placement points at all.
  #
  # Callers ask for the scale FIRST, then request exactly scale.length ranked
  # rows, because full_field's ladder is as long as the field.
  class PointsScale
    def self.call(club:, entry_count:)
      return nil if entry_count.to_i < club.season_points_min_entries

      case club.season_points_scheme
      when "tiered_ladders" then club.season_points_ladders[band_index(entry_count)]
      when "base_ladder"    then scaled_base_ladder(club, entry_count)
      when "full_field"     then entry_count.to_i.downto(1).to_a
      end
    end

    def self.band_index(entry_count)
      ::Club::SEASON_POINTS_BANDS.index { |band| band.cover?(entry_count.to_i) } ||
        ::Club::SEASON_POINTS_BANDS.size - 1
    end
    private_class_method :band_index

    def self.scaled_base_ladder(club, entry_count)
      multiplier = club.season_points_tier_multipliers[band_index(entry_count)].to_f
      club.season_points_base_ladder.map { |amount| (amount.to_f * multiplier).round(2) }
    end
    private_class_method :scaled_base_ladder
  end
end
