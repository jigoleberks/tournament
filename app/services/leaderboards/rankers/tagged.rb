module Leaderboards
  module Rankers
    class Tagged
      # Sentinel for entries with no catches: sort them after every real
      # timestamp. Constructed at load time because Time.zone is fixed to
      # UTC in this app; allocating it per .call would be wasteful.
      FAR_FUTURE = (::Time.zone.at(0) + 100.years).freeze

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
