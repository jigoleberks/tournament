module Leaderboards
  module Rankers
    class Tagged
      # Ranks entries by ticket count (= active placements count) desc.
      # Tiebreak: earliest first-catch timestamp asc → entry.id asc.
      # The :total key carries the ticket count so the leaderboard partial
      # can use a single accessor regardless of format.
      def self.call(entry_rows)
        entry_rows.map do |row|
          row.merge(total: row[:fish].size)
        end.sort_by do |r|
          [
            -r[:total],
            r[:earliest_catch_at] || FAR_FUTURE,
            r[:entry].id
          ]
        end
      end
    end
  end
end
