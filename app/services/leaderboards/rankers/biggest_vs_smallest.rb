module Leaderboards
  module Rankers
    class BiggestVsSmallest
      # Score: max(length) - min(length) per entry within the configured species.
      # Largest spread wins. Entries with 0 or 1 catches are "incomplete" and sort
      # below all 2+ catch entries (single-catch spread is reported as 0).
      # Tiebreak: spread desc → earliest captured_at_device asc → entry.id asc.
      # Row :fish is returned biggest-first so the leaderboard partial can render
      # the two extremes in that order without re-sorting.
      def self.call(entry_rows)
        far_future = ::Time.zone.at(0) + 100.years
        rows = entry_rows.map do |row|
          fish = row[:fish]
          if fish.size >= 2
            lens   = fish.map { |f| f[:length_inches] }
            sorted = fish.sort_by { |f| -f[:length_inches] }  # biggest first
            spread = lens.max - lens.min
            {
              entry: row[:entry],
              total: spread,
              fish: sorted,
              fish_lengths: sorted.map { |f| f[:length_inches] },
              earliest_catch_at: fish.map { |f| f[:captured_at_device] }.compact.min,
              complete: true
            }
          elsif fish.size == 1
            f = fish.first
            {
              entry: row[:entry],
              total: 0,
              fish: [f],
              fish_lengths: [f[:length_inches]],
              earliest_catch_at: f[:captured_at_device],
              complete: false
            }
          else
            {
              entry: row[:entry], total: nil, fish: [], fish_lengths: [],
              earliest_catch_at: nil, complete: false
            }
          end
        end
        rows.sort_by do |r|
          [
            r[:complete] ? 0 : 1,
            -(r[:total] || 0),
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end
      end
    end
  end
end
