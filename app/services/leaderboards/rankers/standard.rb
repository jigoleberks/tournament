module Leaderboards
  module Rankers
    class Standard
      # Cascade tiebreaker: complete tier first → total desc → largest single fish desc →
      # 2nd largest desc → ... → earliest captured_at_device asc → entry.id asc.
      def self.call(rows, tournament: nil)
        _ = tournament  # accepted for ranker uniformity; Standard does not use it
        max_fish = rows.map { |r| r[:fish].size }.max || 0
        far_future = ::Time.zone.at(0) + 100.years
        rows.sort_by do |r|
          fish_desc = r[:fish].map { |f| f[:length_inches] }.sort.reverse
          fish_padded = fish_desc + [0] * (max_fish - fish_desc.size)
          [
            r[:complete] ? 0 : 1,
            -r[:total],
            *fish_padded.map { |l| -l },
            r[:earliest_catch_at] || far_future,
            r[:entry].id
          ]
        end
      end
    end
  end
end
