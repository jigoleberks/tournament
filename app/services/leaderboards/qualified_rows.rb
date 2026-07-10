module Leaderboards
  # Ranked leaderboard rows filtered to entries that actually participated,
  # preserving rank order. Length/standard formats have a :fish array (empty =
  # no scoring catch); bingo rows have no :fish — an entry that only holds the
  # free centre square (squares_count == 1) hasn't progressed. Progressive
  # Length scores up-sizes (fish.size - 1), so a lone fish is 0 up-sizes and
  # hasn't climbed the ladder — it must not qualify for a win or season points
  # (its leaderboard score renders "—"). Shared by the winner/top-three/
  # season-points consumers so bingo's placement-less rows don't hit the
  # :fish path.
  class QualifiedRows
    def self.call(tournament:, rows:)
      if tournament.format_bingo?
        rows.reject { |r| r[:squares_count].to_i <= 1 }
      elsif tournament.format_progressive_length?
        rows.reject { |r| r[:fish].size <= 1 }
      else
        rows.reject { |r| r[:fish].empty? }
      end
    end
  end
end
