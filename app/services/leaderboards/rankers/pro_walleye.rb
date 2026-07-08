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
        TotalLengthCascade.call(rows, tier_complete: false)
      end
    end
  end
end
