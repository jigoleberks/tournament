module Leaderboards
  module Rankers
    class SmallestFish
      # Inverse of Standard. Cascade tiebreaker:
      # complete tier first → more fish first (incompletes only) → total asc →
      # smallest single fish asc → 2nd smallest asc → ... →
      # earliest captured_at_device asc → entry.id asc.
      def self.call(rows)
        max_fish = rows.map { |r| r[:fish].size }.max || 0
        far_future = ::Time.zone.at(0) + 100.years
        rows.sort_by do |r|
          fish_asc = r[:fish].map { |f| f[:length_inches] }.sort
          fish_padded = fish_asc + [::Float::INFINITY] * (max_fish - fish_asc.size)
          [
            r[:complete] ? 0 : 1,
            -r[:fish].size,
            r[:total],
            *fish_padded,
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end
      end
    end
  end
end
