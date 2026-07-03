module Leaderboards
  module Rankers
    class ProWalleye
      # Pure total-length ranking for the Pro Walleye slot-limit format: the
      # heaviest bag wins regardless of fish count. Unlike Standard, this does
      # NOT tier complete baskets ahead of incomplete ones — a heavier 4-fish
      # partial outranks a lighter full 5-fish basket. Cascade tiebreaker:
      # total desc → largest single fish desc → 2nd largest desc → ... →
      # earliest captured_at_device asc → entry.id asc.
      def self.call(rows)
        max_fish = rows.map { |r| r[:fish].size }.max || 0
        rows.sort_by do |r|
          fish_desc = r[:fish].map { |f| f[:length_inches] }.sort.reverse
          fish_padded = fish_desc + [0] * (max_fish - fish_desc.size)
          [
            -r[:total],
            *fish_padded.map { |l| -l },
            r[:earliest_catch_at] || FAR_FUTURE,
            r[:entry].id
          ]
        end
      end
    end
  end
end
