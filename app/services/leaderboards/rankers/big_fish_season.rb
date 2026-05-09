module Leaderboards
  module Rankers
    class BigFishSeason
      # Rank by single biggest fish, tiebreaking through 2nd biggest, 3rd biggest,
      # then earliest captured_at_device, then entry.id. No `complete?` or `total` term:
      # one 30" walleye outranks three 25" walleye regardless of slot fill.
      def self.call(rows, tournament:)
        max_fish = rows.map { |r| r[:fish].size }.max || 0
        far_future = ::Time.zone.at(0) + 100.years
        rows.sort_by do |r|
          fish_desc = r[:fish].map { |f| f[:length_inches] }.sort.reverse
          fish_padded = fish_desc + [0] * (max_fish - fish_desc.size)
          [
            *fish_padded.map { |l| -l },
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end
      end
    end
  end
end
