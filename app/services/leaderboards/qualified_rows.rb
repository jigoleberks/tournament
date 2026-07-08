module Leaderboards
  # Ranked leaderboard rows filtered to entries that actually participated,
  # preserving rank order. Length/standard formats have a :fish array (empty =
  # no scoring catch); bingo rows have no :fish — an entry that only holds the
  # free centre square (squares_count == 1) hasn't progressed. Shared by the
  # winner/top-three/season-points consumers so bingo's placement-less rows
  # don't hit the :fish path.
  class QualifiedRows
    def self.call(tournament:, rows:)
      if tournament.format_bingo?
        rows.reject { |r| r[:squares_count].to_i <= 1 }
      else
        rows.reject { |r| r[:fish].empty? }
      end
    end
  end
end
